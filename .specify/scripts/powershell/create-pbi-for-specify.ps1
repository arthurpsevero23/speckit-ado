#!/usr/bin/env pwsh
<#
.SYNOPSIS
Create a Product Backlog Item in Azure DevOps from current spec context or explicit arguments.

.DESCRIPTION
Reads the active feature spec and extracts candidate PBI fields, then applies explicit
arguments as overrides. Supports dry-run preview and JSON output for agent automation.

.PARAMETER Title
PBI title override.

.PARAMETER Description
PBI description override.

.PARAMETER AcceptanceCriteria
PBI acceptance criteria override.

.PARAMETER Tags
Semicolon-separated tags override.

.PARAMETER StoryPoints
Numeric estimate override.

.PARAMETER Priority
Priority override.

.PARAMETER State
Initial state override.

.PARAMETER Sprint
Iteration path override.

.PARAMETER SetAsSelected
Also mirror the created item into selected-pbi.json for immediate downstream usage.

.PARAMETER DryRun
Preview payload without creating a work item.

.PARAMETER Json
Emit machine-readable JSON output.
#>

[CmdletBinding()]
param(
    [string]$Title = "",
    [string]$Description = "",
    [string]$AcceptanceCriteria = "",
    [string]$Tags = "",
    [double]$StoryPoints,
    [int]$Priority,
    [string]$State = "",
    [string]$Sprint = "",
    [string]$WorkItemType = "",
    [switch]$CreateHierarchy,
    [switch]$SetAsSelected,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$PLACEHOLDER_PATTERNS = @(
    '^\[FEATURE NAME\]$'
    '^\[Description captured from Azure DevOps\]$'
    '^\[Acceptance criteria captured from Azure DevOps\]$'
    '^\[PBI title\]$'
    '^\[Tag list\]$'
    '^\[Numeric estimate\]$'
    '^\[AB#XXXX\]$'
    '^\[ID\]$'
)

function Find-SpecKitRoot {
    $currentDir = Get-Location
    if ($currentDir -isnot [System.IO.DirectoryInfo]) {
        $currentDir = Get-Item $currentDir
    }

    $dir = $currentDir
    while ($dir) {
        if (Test-Path (Join-Path $dir '.specify')) {
            return $dir
        }
        $dir = $dir.Parent
        if (-not $dir) { break }
    }

    return $null
}

function Test-IsPlaceholder {
    param([string]$Value)
    if (-not $Value) { return $true }

    $trimmed = $Value.Trim()
    foreach ($pattern in $PLACEHOLDER_PATTERNS) {
        if ($trimmed -match $pattern) { return $true }
    }

    return $false
}

function ConvertTo-AdoHtml {
    param([string]$Text)
    $trimmed = $Text.Trim()
    if (-not $trimmed) { return '' }
    if ($trimmed -match '^<') { return $trimmed }
    return "<pre>$([System.Web.HttpUtility]::HtmlEncode($trimmed))</pre>"
}

function Extract-SectionText {
    param(
        [string[]]$Lines,
        [string]$Heading
    )

    $buffer = [System.Collections.Generic.List[string]]::new()
    $inside = $false

    foreach ($line in $Lines) {
        if ($line -match "^###\s+$([regex]::Escape($Heading))\s*$") {
            $inside = $true
            continue
        }
        if ($inside) {
            if ($line -match '^#{2,3}\s') { break }
            $buffer.Add($line)
        }
    }

    $result = ($buffer | Where-Object { $_ -ne $null }) -join "`n"
    return $result.Trim()
}

function Extract-InlineField {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $escapedLabel = [regex]::Escape($Label)
    foreach ($line in $Lines) {
        if ($line -match "^\s*-\s*\*\*$escapedLabel\*\*\s*:\s*(.+)$") {
            return $Matches[1].Trim()
        }
    }

    return ''
}

function Parse-UserStories {
    param([string[]]$Lines)

    $stories = [System.Collections.Generic.List[PSCustomObject]]::new()
    $i = 0

    while ($i -lt $Lines.Count) {
        if ($Lines[$i] -match '^###\s+User Story (\d+)\s+-\s+(.+?)(?:\s*\(Priority:\s*P\d+\))?\s*$') {
            $storyNum   = [int]$Matches[1]
            $storyTitle = $Matches[2].Trim()
            $i++

            $bodyLines = [System.Collections.Generic.List[string]]::new()
            while ($i -lt $Lines.Count) {
                if ($Lines[$i] -match '^#{2,3}\s' -or $Lines[$i] -eq '---') { break }
                $bodyLines.Add($Lines[$i])
                $i++
            }

            # Short description: first non-empty line that is not a bold label
            $shortDesc = ''
            foreach ($bl in $bodyLines) {
                $t = $bl.Trim()
                if ($t -and -not ($t -match '^\*\*')) { $shortDesc = $t; break }
            }

            # Acceptance criteria: content after **Acceptance Scenarios**: header
            $acLines = [System.Collections.Generic.List[string]]::new()
            $inAc    = $false
            foreach ($bl in $bodyLines) {
                if ($bl -match '^\*\*Acceptance Scenarios\*\*') { $inAc = $true; continue }
                if ($inAc) {
                    if ($bl -match '^\*\*[^*]' -and $bl -notmatch '^\*\*Given') { break }
                    $acLines.Add($bl)
                }
            }
            $ac = (($acLines | Where-Object { $_ -ne $null }) -join "`n").Trim()

            $stories.Add([PSCustomObject]@{
                Number             = $storyNum
                Title              = $storyTitle
                Description        = $shortDesc
                AcceptanceCriteria = $ac
            })
        }
        else {
            $i++
        }
    }

    return , $stories
}

Add-Type -AssemblyName System.Web

$specKitRoot = Find-SpecKitRoot
if (-not $specKitRoot) {
    Write-Error "Cannot find .specify folder. Run this script from within a spec-kit workspace."
    exit 1
}

Set-Location $specKitRoot

$initOptionsPath = Join-Path $specKitRoot '.specify\init-options.json'
$modulePath = Join-Path $specKitRoot '.specify\modules\azure-devops-integration.ps1'
$prereqScript = Join-Path $specKitRoot '.specify\scripts\powershell\check-prerequisites.ps1'
$createdContextPath = Join-Path $specKitRoot '.specify\context\created-pbi.json'
$selectedContextPath = Join-Path $specKitRoot '.specify\context\selected-pbi.json'

foreach ($required in @($initOptionsPath, $modulePath)) {
    if (-not (Test-Path $required)) {
        Write-Error "Required file not found: $required"
        exit 1
    }
}

$config = Get-Content $initOptionsPath -Raw | ConvertFrom-Json
if (-not $config.ado -or -not $config.ado.enabled) {
    Write-Error "Azure DevOps integration is not enabled in .specify/init-options.json"
    exit 1
}

if ($config.ado.creation -and $config.ado.creation.persistContextPath) {
    $createdContextPath = Join-Path $specKitRoot ([string]$config.ado.creation.persistContextPath)
}

. $modulePath

$patToken = [Environment]::GetEnvironmentVariable($config.ado.patTokenEnvVar)
if (-not $patToken) {
    Write-Error "PAT token not found in environment variable: $($config.ado.patTokenEnvVar)"
    exit 1
}

$specPath = ''
$specLines = @()
$linkedWiLines = @()

if (Test-Path $prereqScript) {
    try {
        $prereqOutput = & $prereqScript -Json -PathsOnly 2>$null | Out-String
        $prereqJson = $prereqOutput | ConvertFrom-Json
        if ($prereqJson.FEATURE_SPEC -and (Test-Path $prereqJson.FEATURE_SPEC)) {
            $specPath = [string]$prereqJson.FEATURE_SPEC
            $specContent = Get-Content $specPath -Raw
            $specLines = $specContent -split "`r?`n"

            $linkedWiStart = -1
            $linkedWiEnd = $specLines.Count
            for ($i = 0; $i -lt $specLines.Count; $i++) {
                if ($specLines[$i] -match '^##\s+Linked Work Item') {
                    $linkedWiStart = $i
                }
                elseif ($linkedWiStart -ge 0 -and $i -gt $linkedWiStart -and $specLines[$i] -match '^##\s+(?!#)') {
                    $linkedWiEnd = $i
                    break
                }
            }

            if ($linkedWiStart -ge 0) {
                $linkedWiLines = $specLines[$linkedWiStart..($linkedWiEnd - 1)]
            }
        }
    }
    catch {
        # Continue - explicit arguments can still be used.
    }
}

$specTitle = ''
if ($specLines.Count -gt 0) {
    foreach ($line in $specLines) {
        if ($line -match '^#\s+Feature Specification:\s*(.+)$') {
            $specTitle = $Matches[1].Trim()
            break
        }
    }
}

$specDescription = if ($linkedWiLines.Count -gt 0) { Extract-SectionText -Lines $linkedWiLines -Heading 'PBI Description' } else { '' }
$specAC = if ($linkedWiLines.Count -gt 0) { Extract-SectionText -Lines $linkedWiLines -Heading 'PBI Acceptance Criteria' } else { '' }
$specTags = if ($linkedWiLines.Count -gt 0) { Extract-InlineField -Lines $linkedWiLines -Label 'Tags' } else { '' }
$specSPRaw = if ($linkedWiLines.Count -gt 0) { Extract-InlineField -Lines $linkedWiLines -Label 'Story Points / Estimate' } else { '' }

$specSP = $null
if ($specSPRaw) {
    $parsedSp = 0.0
    if ([double]::TryParse($specSPRaw, [ref]$parsedSp)) {
        $specSP = $parsedSp
    }
}

$effectiveTitle = if ($PSBoundParameters.ContainsKey('Title')) { $Title } else { $specTitle }
$effectiveDescription = if ($PSBoundParameters.ContainsKey('Description')) { $Description } else { $specDescription }
$effectiveAC = if ($PSBoundParameters.ContainsKey('AcceptanceCriteria')) { $AcceptanceCriteria } else { $specAC }
$effectiveTags = if ($PSBoundParameters.ContainsKey('Tags')) { $Tags } else { $specTags }
$effectiveSP = if ($PSBoundParameters.ContainsKey('StoryPoints')) { $StoryPoints } else { $specSP }

$defaultPriority = 3
if ($config.ado.creation -and $null -ne $config.ado.creation.defaultPriority) {
    $defaultPriority = [int]$config.ado.creation.defaultPriority
}
$effectivePriority = if ($PSBoundParameters.ContainsKey('Priority')) { $Priority } else { $defaultPriority }

$defaultState = 'New'
if ($config.ado.creation -and $config.ado.creation.defaultState) {
    $defaultState = [string]$config.ado.creation.defaultState
}
$effectiveState = if ($PSBoundParameters.ContainsKey('State')) { $State } else { $defaultState }

$defaultSprint = ''
if ($config.ado.filterByIteration) {
    $defaultSprint = [string]$config.ado.filterByIteration
}
$effectiveSprint = if ($PSBoundParameters.ContainsKey('Sprint')) { $Sprint } else { $defaultSprint }

$defaultWorkItemType = 'Product Backlog Item'
if ($config.ado.creation -and $config.ado.creation.workItemType) {
    $defaultWorkItemType = [string]$config.ado.creation.workItemType
}
$effectiveWorkItemType = if ($PSBoundParameters.ContainsKey('WorkItemType')) { $WorkItemType } else { $defaultWorkItemType }

if ($config.ado.creation -and $config.ado.creation.defaultTags -and -not $PSBoundParameters.ContainsKey('Tags') -and -not $effectiveTags) {
    $effectiveTags = (@($config.ado.creation.defaultTags) -join '; ')
}

if (Test-IsPlaceholder -Value $effectiveTitle) {
    $effectiveTitle = ''
}
if (Test-IsPlaceholder -Value $effectiveDescription) {
    $effectiveDescription = ''
}
if (Test-IsPlaceholder -Value $effectiveAC) {
    $effectiveAC = ''
}
if (Test-IsPlaceholder -Value $effectiveTags) {
    $effectiveTags = ''
}

if (-not $effectiveTitle) {
    Write-Error "No PBI title resolved. Provide -Title or ensure the active spec has a valid feature title."
    exit 1
}

# ─── Hierarchy detection ──────────────────────────────────────────────────────
$hierarchyEnabled  = $false
$epicWorkItemType  = 'Epic'
$epicState         = $effectiveState
$storyWorkItemType = $effectiveWorkItemType
$parsedUserStories = @()

if ($config.ado.creation.PSObject.Properties.Match('hierarchy').Count -gt 0) {
    $hCfg = $config.ado.creation.hierarchy
    if ($hCfg -and $hCfg.createHierarchy -eq $true) { $hierarchyEnabled = $true }
    if ($hCfg.epicWorkItemType) { $epicWorkItemType  = [string]$hCfg.epicWorkItemType }
    if ($hCfg.epicState)        { $epicState         = [string]$hCfg.epicState }
    if ($hCfg.storyWorkItemType){ $storyWorkItemType = [string]$hCfg.storyWorkItemType }
}

if ($PSBoundParameters.ContainsKey('CreateHierarchy') -and $CreateHierarchy) {
    $hierarchyEnabled = $true
}

if ($hierarchyEnabled -and $specLines.Count -gt 0) {
    $parsedUserStories = @(Parse-UserStories -Lines $specLines)
    if ($parsedUserStories.Count -lt 2) {
        $hierarchyEnabled = $false
        if (-not $Json) {
            Write-Host 'Note: fewer than 2 user stories found — using flat creation mode.' -ForegroundColor Yellow
        }
    }
}

$fieldsApplied = [System.Collections.Generic.List[string]]::new()
$fieldsApplied.Add('Title')
if ($effectiveDescription) { $fieldsApplied.Add('Description') }
if ($effectiveAC) { $fieldsApplied.Add('Acceptance Criteria') }
if ($effectiveTags) { $fieldsApplied.Add('Tags') }
if ($null -ne $effectiveSP) { $fieldsApplied.Add('Story Points') }
if ($null -ne $effectivePriority) { $fieldsApplied.Add('Priority') }
if ($effectiveState) { $fieldsApplied.Add('State') }
if ($effectiveSprint) { $fieldsApplied.Add('Iteration') }
if ($effectiveWorkItemType) { $fieldsApplied.Add('Work Item Type') }

if ($DryRun) {
    if ($hierarchyEnabled) {
        $storyPreviews = @($parsedUserStories | ForEach-Object {
            [PSCustomObject]@{
                number       = $_.Number
                title        = "Story $($_.Number) — $($_.Title)"
                workItemType = $storyWorkItemType
                state        = $effectiveState
            }
        })
        $preview = [PSCustomObject]@{
            success    = $true
            dryRun     = $true
            mode       = 'hierarchy'
            epic       = [PSCustomObject]@{
                title        = $effectiveTitle
                workItemType = $epicWorkItemType
                state        = $epicState
            }
            stories    = $storyPreviews
            tags       = $effectiveTags
            sprint     = $effectiveSprint
            sourceSpec = $specPath
            message    = "Dry run: will create 1 $epicWorkItemType + $($parsedUserStories.Count) $storyWorkItemType items. Use without -DryRun to create."
        }
    }
    else {
        $preview = [PSCustomObject]@{
            success            = $true
            dryRun             = $true
            mode               = 'flat'
            title              = $effectiveTitle
            description        = $effectiveDescription
            acceptanceCriteria = $effectiveAC
            tags               = $effectiveTags
            storyPoints        = $effectiveSP
            priority           = $effectivePriority
            state              = $effectiveState
            sprint             = $effectiveSprint
            workItemType       = $effectiveWorkItemType
            fieldsApplied      = @($fieldsApplied)
            sourceSpec         = $specPath
            message            = 'Dry run complete. Use without -DryRun to create the PBI.'
        }
    }

    if ($Json) {
        $preview | ConvertTo-Json -Depth 7
    }
    else {
        Write-Host ''
        Write-Host 'DRY RUN - no work items will be created' -ForegroundColor Yellow
        if ($hierarchyEnabled) {
            Write-Host 'Mode: HIERARCHY' -ForegroundColor Cyan
            Write-Host ("Epic ($epicWorkItemType): {0}" -f $effectiveTitle)
            foreach ($s in $parsedUserStories) {
                Write-Host ("  Child ($storyWorkItemType): Story $($s.Number) — $($s.Title)")
            }
        }
        else {
            Write-Host 'Mode: FLAT'
            Write-Host ("Title: {0}" -f $effectiveTitle)
            Write-Host ("Fields: {0}" -f ($fieldsApplied -join ', '))
        }
        if ($specPath) {
            Write-Host ("Source spec: {0}" -f $specPath) -ForegroundColor Gray
        }
    }

    exit 0
}

$adoDescription = if ($effectiveDescription) { ConvertTo-AdoHtml -Text $effectiveDescription } else { '' }
$adoAC          = if ($effectiveAC)           { ConvertTo-AdoHtml -Text $effectiveAC }           else { '' }

$createdDir = Split-Path -Parent $createdContextPath
if (-not (Test-Path $createdDir)) {
    New-Item -Path $createdDir -ItemType Directory -Force | Out-Null
}

# ─── Hierarchy creation ───────────────────────────────────────────────────────
if ($hierarchyEnabled) {
    # 1. Create the Epic
    $epicParams = @{
        Organization = [string]$config.ado.organization
        ProjectName  = [string]$config.ado.projectName
        PatToken     = $patToken
        Title        = $effectiveTitle
        Priority     = $effectivePriority
        State        = $epicState
        Iteration    = $effectiveSprint
        WorkItemType = $epicWorkItemType
    }
    if ($adoDescription) { $epicParams['Description'] = $adoDescription }
    if ($effectiveTags)  { $epicParams['Tags']        = $effectiveTags }

    $createdEpic = New-AzureDevOpsPBI @epicParams
    $epicId      = [int]$createdEpic.id
    $epicTitle   = [string]$createdEpic.fields.'System.Title'
    $epicUrl     = "https://dev.azure.com/$($config.ado.organization)/$($config.ado.projectName)/_workitems/edit/$epicId"

    # 2. Create one child work item per user story and link to epic
    $childItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($story in $parsedUserStories) {
        $childTitle    = "Story $($story.Number) — $($story.Title)"
        $childDescHtml = if ($story.Description)        { ConvertTo-AdoHtml -Text $story.Description }        else { '' }
        $childAcHtml   = if ($story.AcceptanceCriteria) { ConvertTo-AdoHtml -Text $story.AcceptanceCriteria } else { '' }

        $childParams = @{
            Organization = [string]$config.ado.organization
            ProjectName  = [string]$config.ado.projectName
            PatToken     = $patToken
            Title        = $childTitle
            Priority     = $effectivePriority
            State        = $effectiveState
            Iteration    = $effectiveSprint
            WorkItemType = $storyWorkItemType
        }
        if ($childDescHtml) { $childParams['Description']        = $childDescHtml }
        if ($childAcHtml)   { $childParams['AcceptanceCriteria'] = $childAcHtml }
        if ($effectiveTags) { $childParams['Tags']               = $effectiveTags }

        $createdChild = New-AzureDevOpsPBI @childParams
        $childId      = [int]$createdChild.id

        Set-WorkItemParent -Organization ([string]$config.ado.organization) `
                           -ProjectName  ([string]$config.ado.projectName)  `
                           -PatToken     $patToken                           `
                           -ChildId      $childId                            `
                           -ParentId     $epicId

        $childUrl = "https://dev.azure.com/$($config.ado.organization)/$($config.ado.projectName)/_workitems/edit/$childId"
        $childItems.Add([PSCustomObject]@{
            id          = $childId
            taskId      = (ConvertTo-TaskId -PBIId $childId)
            title       = $childTitle
            storyNumber = $story.Number
            url         = $childUrl
        })
    }

    # 3. Persist hierarchy context
    $hierarchyContext = [PSCustomObject]@{
        createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = 'hierarchy'
        source       = [PSCustomObject]@{
            organization = [string]$config.ado.organization
            projectName  = [string]$config.ado.projectName
        }
        spec         = [PSCustomObject]@{ path = $specPath }
        epic         = [PSCustomObject]@{
            id           = $epicId
            taskId       = (ConvertTo-TaskId -PBIId $epicId)
            title        = $epicTitle
            workItemType = $epicWorkItemType
            url          = $epicUrl
        }
        children     = @($childItems)
    }
    $hierarchyContext | ConvertTo-Json -Depth 10 | Set-Content -Path $createdContextPath -Encoding UTF8

    if ($SetAsSelected -and $childItems.Count -gt 0) {
        $first  = $childItems[0]
        $selCtx = [PSCustomObject]@{
            selectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            source        = [PSCustomObject]@{
                organization = [string]$config.ado.organization
                projectName  = [string]$config.ado.projectName
            }
            filters = [PSCustomObject]@{
                state      = @($effectiveState)
                sprint     = $effectiveSprint
                assignedTo = ''
                searchText = ''
            }
            pbi = [PSCustomObject]@{
                id                 = $first.id
                taskId             = $first.taskId
                title              = $first.title
                description        = ''
                acceptanceCriteria = ''
                state              = $effectiveState
                assignedTo         = ''
                iteration          = $effectiveSprint
                tags               = $effectiveTags
                storyPoints        = $null
            }
        }
        $selCtx | ConvertTo-Json -Depth 10 | Set-Content -Path $selectedContextPath -Encoding UTF8
    }

    $result = [PSCustomObject]@{
        success            = $true
        dryRun             = $false
        mode               = 'hierarchy'
        epicId             = $epicId
        epicTaskId         = (ConvertTo-TaskId -PBIId $epicId)
        epicTitle          = $epicTitle
        epicUrl            = $epicUrl
        children           = @($childItems)
        createdContextPath = $createdContextPath
        setAsSelected      = $SetAsSelected.IsPresent
    }

    if ($Json) {
        $result | ConvertTo-Json -Depth 10
    }
    else {
        Write-Host ''
        Write-Host ("Created Epic  AB#{0}: {1}" -f $epicId, $epicTitle) -ForegroundColor Cyan
        Write-Host ("  URL: {0}" -f $epicUrl)
        foreach ($c in $childItems) {
            Write-Host ("Created Issue AB#{0}: {1}" -f $c.id, $c.title) -ForegroundColor Green
            Write-Host ("  URL: {0}" -f $c.url)
        }
        Write-Host ("Context saved: {0}" -f $createdContextPath) -ForegroundColor Gray
        if ($SetAsSelected) {
            Write-Host ("Selected context updated (first child): {0}" -f $selectedContextPath) -ForegroundColor Gray
        }
    }
}
else {
    # ─── Flat creation (original behavior) ────────────────────────────────────
    $createParams = @{
        Organization = [string]$config.ado.organization
        ProjectName  = [string]$config.ado.projectName
        PatToken     = $patToken
        Title        = $effectiveTitle
        Priority     = $effectivePriority
        State        = $effectiveState
        Iteration    = $effectiveSprint
        WorkItemType = $effectiveWorkItemType
    }
    if ($adoDescription) { $createParams['Description']        = $adoDescription }
    if ($adoAC)          { $createParams['AcceptanceCriteria'] = $adoAC }
    if ($effectiveTags)  { $createParams['Tags']               = $effectiveTags }
    if ($null -ne $effectiveSP) { $createParams['StoryPoints'] = $effectiveSP }

    $created      = New-AzureDevOpsPBI @createParams
    $pbiId        = [int]$created.id
    $pbiTitle     = [string]$created.fields.'System.Title'
    $pbiState     = if ($created.fields.PSObject.Properties.Match('System.State').Count -gt 0)         { [string]$created.fields.'System.State' }         else { '' }
    $pbiIteration = if ($created.fields.PSObject.Properties.Match('System.IterationPath').Count -gt 0) { [string]$created.fields.'System.IterationPath' } else { '' }
    $pbiTags      = if ($created.fields.PSObject.Properties.Match('System.Tags').Count -gt 0)          { [string]$created.fields.'System.Tags' }          else { '' }
    $pbiUrl       = "https://dev.azure.com/$($config.ado.organization)/$($config.ado.projectName)/_workitems/edit/$pbiId"

    $createdContext = [PSCustomObject]@{
        createdAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
        mode          = 'flat'
        source        = [PSCustomObject]@{
            organization = [string]$config.ado.organization
            projectName  = [string]$config.ado.projectName
        }
        spec          = [PSCustomObject]@{ path = $specPath }
        pbi           = [PSCustomObject]@{
            id          = $pbiId
            taskId      = (ConvertTo-TaskId -PBIId $pbiId)
            title       = $pbiTitle
            state       = $pbiState
            iteration   = $pbiIteration
            tags        = $pbiTags
            storyPoints = if ($null -ne $effectiveSP) { $effectiveSP } else { $null }
            url         = $pbiUrl
        }
        fieldsApplied = @($fieldsApplied)
    }
    $createdContext | ConvertTo-Json -Depth 10 | Set-Content -Path $createdContextPath -Encoding UTF8

    if ($SetAsSelected) {
        $selectedContext = [PSCustomObject]@{
            selectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            source        = [PSCustomObject]@{
                organization = [string]$config.ado.organization
                projectName  = [string]$config.ado.projectName
            }
            filters = [PSCustomObject]@{
                state      = @($pbiState)
                sprint     = $pbiIteration
                assignedTo = ''
                searchText = ''
            }
            pbi = [PSCustomObject]@{
                id                 = $pbiId
                taskId             = (ConvertTo-TaskId -PBIId $pbiId)
                title              = $pbiTitle
                description        = $effectiveDescription
                acceptanceCriteria = $effectiveAC
                state              = $pbiState
                assignedTo         = ''
                iteration          = $pbiIteration
                tags               = $pbiTags
                storyPoints        = if ($null -ne $effectiveSP) { $effectiveSP } else { $null }
            }
        }
        $selectedContext | ConvertTo-Json -Depth 10 | Set-Content -Path $selectedContextPath -Encoding UTF8
    }

    $result = [PSCustomObject]@{
        success            = $true
        dryRun             = $false
        mode               = 'flat'
        pbiId              = $pbiId
        taskId             = (ConvertTo-TaskId -PBIId $pbiId)
        title              = $pbiTitle
        url                = $pbiUrl
        fieldsApplied      = @($fieldsApplied)
        createdContextPath = $createdContextPath
        setAsSelected      = $SetAsSelected.IsPresent
    }

    if ($Json) {
        $result | ConvertTo-Json -Depth 8
    }
    else {
        Write-Host ''
        Write-Host ("Created PBI AB#{0}: {1}" -f $pbiId, $pbiTitle) -ForegroundColor Green
        Write-Host ("Work item URL: {0}" -f $pbiUrl) -ForegroundColor Cyan
        Write-Host ("Context saved: {0}" -f $createdContextPath) -ForegroundColor Gray
        if ($SetAsSelected) {
            Write-Host ("Selected context updated: {0}" -f $selectedContextPath) -ForegroundColor Gray
        }
    }
}
