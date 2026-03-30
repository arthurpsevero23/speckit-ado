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
    $preview = [PSCustomObject]@{
        success = $true
        dryRun = $true
        title = $effectiveTitle
        description = $effectiveDescription
        acceptanceCriteria = $effectiveAC
        tags = $effectiveTags
        storyPoints = $effectiveSP
        priority = $effectivePriority
        state = $effectiveState
        sprint = $effectiveSprint
        workItemType = $effectiveWorkItemType
        fieldsApplied = @($fieldsApplied)
        sourceSpec = $specPath
        message = 'Dry run complete. Use without -DryRun to create the PBI.'
    }

    if ($Json) {
        $preview | ConvertTo-Json -Depth 7
    }
    else {
        Write-Host ''
        Write-Host 'DRY RUN - no work item will be created' -ForegroundColor Yellow
        Write-Host ("Title: {0}" -f $effectiveTitle)
        Write-Host ("Fields: {0}" -f ($fieldsApplied -join ', '))
        if ($specPath) {
            Write-Host ("Source spec: {0}" -f $specPath) -ForegroundColor Gray
        }
    }

    exit 0
}

$adoDescription = if ($effectiveDescription) { ConvertTo-AdoHtml -Text $effectiveDescription } else { '' }
$adoAC = if ($effectiveAC) { ConvertTo-AdoHtml -Text $effectiveAC } else { '' }

$createParams = @{
    Organization = [string]$config.ado.organization
    ProjectName = [string]$config.ado.projectName
    PatToken = $patToken
    Title = $effectiveTitle
    Priority = $effectivePriority
    State = $effectiveState
    Iteration = $effectiveSprint
    WorkItemType = $effectiveWorkItemType
}
if ($adoDescription) { $createParams['Description'] = $adoDescription }
if ($adoAC) { $createParams['AcceptanceCriteria'] = $adoAC }
if ($effectiveTags) { $createParams['Tags'] = $effectiveTags }
if ($null -ne $effectiveSP) { $createParams['StoryPoints'] = $effectiveSP }

$created = New-AzureDevOpsPBI @createParams
$pbiId = [int]$created.id
$pbiTitle = [string]$created.fields.'System.Title'
$pbiState = if ($created.fields.PSObject.Properties.Match('System.State').Count -gt 0) { [string]$created.fields.'System.State' } else { '' }
$pbiIteration = if ($created.fields.PSObject.Properties.Match('System.IterationPath').Count -gt 0) { [string]$created.fields.'System.IterationPath' } else { '' }
$pbiTags = if ($created.fields.PSObject.Properties.Match('System.Tags').Count -gt 0) { [string]$created.fields.'System.Tags' } else { '' }
$pbiUrl = "https://dev.azure.com/$($config.ado.organization)/$($config.ado.projectName)/_workitems/edit/$pbiId"

$createdContext = [PSCustomObject]@{
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    source = [PSCustomObject]@{
        organization = [string]$config.ado.organization
        projectName = [string]$config.ado.projectName
    }
    spec = [PSCustomObject]@{
        path = $specPath
    }
    pbi = [PSCustomObject]@{
        id = $pbiId
        taskId = (ConvertTo-TaskId -PBIId $pbiId)
        title = $pbiTitle
        state = $pbiState
        iteration = $pbiIteration
        tags = $pbiTags
        storyPoints = if ($null -ne $effectiveSP) { $effectiveSP } else { $null }
        url = $pbiUrl
    }
    fieldsApplied = @($fieldsApplied)
}

$createdDir = Split-Path -Parent $createdContextPath
if (-not (Test-Path $createdDir)) {
    New-Item -Path $createdDir -ItemType Directory -Force | Out-Null
}
$createdContext | ConvertTo-Json -Depth 10 | Set-Content -Path $createdContextPath -Encoding UTF8

if ($SetAsSelected) {
    $selectedContext = [PSCustomObject]@{
        selectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        source = [PSCustomObject]@{
            organization = [string]$config.ado.organization
            projectName = [string]$config.ado.projectName
        }
        filters = [PSCustomObject]@{
            state = @($pbiState)
            sprint = $pbiIteration
            assignedTo = ''
            searchText = ''
        }
        pbi = [PSCustomObject]@{
            id = $pbiId
            taskId = (ConvertTo-TaskId -PBIId $pbiId)
            title = $pbiTitle
            description = $effectiveDescription
            acceptanceCriteria = $effectiveAC
            state = $pbiState
            assignedTo = ''
            iteration = $pbiIteration
            tags = $pbiTags
            storyPoints = if ($null -ne $effectiveSP) { $effectiveSP } else { $null }
        }
    }
    $selectedContext | ConvertTo-Json -Depth 10 | Set-Content -Path $selectedContextPath -Encoding UTF8
}

$result = [PSCustomObject]@{
    success = $true
    dryRun = $false
    pbiId = $pbiId
    taskId = (ConvertTo-TaskId -PBIId $pbiId)
    title = $pbiTitle
    url = $pbiUrl
    fieldsApplied = @($fieldsApplied)
    createdContextPath = $createdContextPath
    setAsSelected = $SetAsSelected.IsPresent
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
