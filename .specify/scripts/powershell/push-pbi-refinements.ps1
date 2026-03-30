#!/usr/bin/env pwsh
<#
.SYNOPSIS
Push refined PBI fields from spec.md back to Azure DevOps.

.DESCRIPTION
Reads the "Linked Work Item" section of the active feature's spec.md,
extracts refined Description, Acceptance Criteria, Story Points and Tags,
then PATCHes the corresponding ADO work item and posts a comment documenting
the refinement.

The script relies on:
  - .specify/context/selected-pbi.json  (written by select-pbi-for-specify.ps1)
  - check-prerequisites.ps1             (to resolve the active feature spec path)
  - azure-devops-integration.ps1        (module: Update-AzureDevOpsPBI, Add-AzureDevOpsPBIComment)

.PARAMETER DryRun
Show what would be pushed without making any API calls.

.PARAMETER Json
Output result as a JSON object instead of human-readable text.

.EXAMPLE
./push-pbi-refinements.ps1 -DryRun

.EXAMPLE
./push-pbi-refinements.ps1 -Json
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Placeholders — values copied verbatim from spec-template.md that must NOT
# be pushed back to ADO.
# ---------------------------------------------------------------------------
$PLACEHOLDER_PATTERNS = @(
    '^\[Description captured from Azure DevOps\]$'
    '^\[Acceptance criteria captured from Azure DevOps\]$'
    '^\[AB#XXXX\]$'
    '^\[ID\]$'
    '^\[PBI title\]$'
    '^\[Tag list\]$'
    '^\[Numeric estimate\]$'
    '^N/A$'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Find-SpecKitRoot {
    $currentDir = Get-Location
    if ($currentDir -isnot [System.IO.DirectoryInfo]) {
        $currentDir = Get-Item $currentDir
    }
    $dir = $currentDir
    while ($dir) {
        if (Test-Path (Join-Path $dir '.specify')) { return $dir }
        $dir = $dir.Parent
        if (-not $dir) { break }
    }
    return $null
}

function Test-IsPlaceholder {
    param([string]$Value)
    foreach ($pattern in $PLACEHOLDER_PATTERNS) {
        if ($Value.Trim() -match $pattern) { return $true }
    }
    return $false
}

function ConvertTo-AdoHtml {
    <#
    .SYNOPSIS
    Wrap plain markdown text in <pre> so ADO renders it readably.
    HTML tags already present are passed through as-is.
    #>
    param([string]$Text)
    $trimmed = $Text.Trim()
    if ($trimmed -match '^<') {
        return $trimmed
    }
    return "<pre>$([System.Web.HttpUtility]::HtmlEncode($trimmed))</pre>"
}

function Extract-SectionText {
    <#
    .SYNOPSIS
    Extract all lines belonging to a markdown section (### Heading) until
    the next ### or ## heading.
    Returns a trimmed, non-empty string or empty string if not found / placeholder.
    #>
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
            # Stop at the next heading (## or ###)
            if ($line -match '^#{2,3}\s') { break }
            $buffer.Add($line)
        }
    }

    $result = ($buffer | Where-Object { $_ -ne $null }) -join "`n"
    $result = $result.Trim()

    if (-not $result -or (Test-IsPlaceholder -Value $result)) {
        return ""
    }
    return $result
}

function Extract-InlineField {
    <#
    .SYNOPSIS
    Extract the value after "- **Label**:" from Linked Work Item bullet lines.
    Returns empty string when absent or placeholder.
    #>
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $escapedLabel = [regex]::Escape($Label)
    foreach ($line in $Lines) {
        if ($line -match "^\s*-\s*\*\*$escapedLabel\*\*\s*:\s*(.+)$") {
            $value = $Matches[1].Trim()
            if (-not $value -or (Test-IsPlaceholder -Value $value)) { return "" }
            return $value
        }
    }
    return ""
}

# ---------------------------------------------------------------------------
# Load system.web for HtmlEncode (available in .NET even on PS 5.1)
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Web

# ---------------------------------------------------------------------------
# Locate spec-kit root
# ---------------------------------------------------------------------------

$specKitRoot = Find-SpecKitRoot
if (-not $specKitRoot) {
    Write-Error "Cannot find .specify folder. Run this script from within a spec-kit workspace."
    exit 1
}

Set-Location $specKitRoot

$initOptionsPath = Join-Path $specKitRoot '.specify\init-options.json'
$modulePath      = Join-Path $specKitRoot '.specify\modules\azure-devops-integration.ps1'
$contextPath     = Join-Path $specKitRoot '.specify\context\selected-pbi.json'
$prereqScript    = Join-Path $specKitRoot '.specify\scripts\powershell\check-prerequisites.ps1'

foreach ($required in @($initOptionsPath, $modulePath)) {
    if (-not (Test-Path $required)) {
        Write-Error "Required file not found: $required"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Load config + PAT
# ---------------------------------------------------------------------------

$config = Get-Content $initOptionsPath -Raw | ConvertFrom-Json
if (-not $config.ado -or -not $config.ado.enabled) {
    Write-Error "Azure DevOps integration is not enabled in init-options.json"
    exit 1
}

. $modulePath

$patToken = [Environment]::GetEnvironmentVariable($config.ado.patTokenEnvVar)
if (-not $patToken) {
    Write-Error "PAT token not found in environment variable: $($config.ado.patTokenEnvVar)"
    exit 1
}

# ---------------------------------------------------------------------------
# Read selected-pbi.json
# ---------------------------------------------------------------------------

if (-not (Test-Path $contextPath)) {
    Write-Error "No selected PBI context found at: $contextPath`nRun select-pbi-for-specify.ps1 (or /speckit.pickup-task) first."
    exit 1
}

$pbiContext = Get-Content $contextPath -Raw | ConvertFrom-Json
$pbiId      = [int]$pbiContext.pbi.id
$org        = [string]$pbiContext.source.organization
$project    = [string]$pbiContext.source.projectName

if ($pbiId -eq 0) {
    Write-Error "Invalid PBI ID in selected-pbi.json (got 0)."
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve feature spec path via check-prerequisites.ps1
# ---------------------------------------------------------------------------

$specPath = $null

if (Test-Path $prereqScript) {
    try {
        $prereqOutput = & $prereqScript -Json -PathsOnly 2>$null | Out-String
        $prereqJson = $prereqOutput | ConvertFrom-Json
        if ($prereqJson.FEATURE_SPEC -and (Test-Path $prereqJson.FEATURE_SPEC)) {
            $specPath = $prereqJson.FEATURE_SPEC
        }
    }
    catch {
        # prereq script failed — will fall through to error below
    }
}

if (-not $specPath) {
    Write-Error "Could not determine the active feature spec path.`nMake sure you are on a feature branch and have run /speckit.specify."
    exit 1
}

# ---------------------------------------------------------------------------
# Parse spec.md — Linked Work Item section
# ---------------------------------------------------------------------------

$specContent = Get-Content $specPath -Raw
$specLines   = $specContent -split "`r?`n"

# Find the start/end of ## Linked Work Item section
$linkedWiStart = -1
$linkedWiEnd   = $specLines.Count

for ($i = 0; $i -lt $specLines.Count; $i++) {
    if ($specLines[$i] -match '^##\s+Linked Work Item') {
        $linkedWiStart = $i
    }
    elseif ($linkedWiStart -ge 0 -and $i -gt $linkedWiStart -and $specLines[$i] -match '^##\s+(?!#)') {
        $linkedWiEnd = $i
        break
    }
}

if ($linkedWiStart -lt 0) {
    Write-Error "spec.md does not contain a '## Linked Work Item' section.`nMake sure the spec was generated with PBI context."
    exit 1
}

$linkedWiLines = $specLines[$linkedWiStart..($linkedWiEnd - 1)]

# Extract fields
$rawDescription = Extract-SectionText -Lines $linkedWiLines -Heading "PBI Description"
$rawAC          = Extract-SectionText -Lines $linkedWiLines -Heading "PBI Acceptance Criteria"
$rawTags        = Extract-InlineField  -Lines $linkedWiLines -Label "Tags"
$rawSP          = Extract-InlineField  -Lines $linkedWiLines -Label "Story Points / Estimate"

# Convert story points to numeric (null if not parseable)
$storyPoints = $null
if ($rawSP) {
    $spParsed = 0.0
    if ([double]::TryParse($rawSP, [ref]$spParsed)) {
        $storyPoints = $spParsed
    }
}

# Wrap text fields for ADO HTML fields
$adoDescription = if ($rawDescription) { ConvertTo-AdoHtml -Text $rawDescription } else { "" }
$adoAC          = if ($rawAC)          { ConvertTo-AdoHtml -Text $rawAC }          else { "" }

# Build list of fields that will actually be updated
$fieldsToUpdate = [System.Collections.Generic.List[string]]::new()
if ($adoDescription) { $fieldsToUpdate.Add("Description") }
if ($adoAC)          { $fieldsToUpdate.Add("Acceptance Criteria") }
if ($rawTags)        { $fieldsToUpdate.Add("Tags") }
if ($null -ne $storyPoints) { $fieldsToUpdate.Add("Story Points") }

if ($fieldsToUpdate.Count -eq 0) {
    $result = [PSCustomObject]@{
        success       = $false
        pbiId         = $pbiId
        fieldsUpdated = @()
        commentPosted = $false
        dryRun        = $DryRun.IsPresent
        message       = "No refineable fields found in the Linked Work Item section (all values are placeholders or empty)."
    }
    if ($Json) {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-Warning $result.message
    }
    exit 0
}

# ---------------------------------------------------------------------------
# DryRun output
# ---------------------------------------------------------------------------

if ($DryRun) {
    if (-not $Json) {
        Write-Host ""
        Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
        Write-Host ("PBI: AB#{0}" -f $pbiId) -ForegroundColor Cyan
        Write-Host ("Fields to update: {0}" -f ($fieldsToUpdate -join ', ')) -ForegroundColor Cyan
        Write-Host ""
        if ($adoDescription) {
            Write-Host "--- Description ---" -ForegroundColor Gray
            Write-Host $rawDescription
            Write-Host ""
        }
        if ($adoAC) {
            Write-Host "--- Acceptance Criteria ---" -ForegroundColor Gray
            Write-Host $rawAC
            Write-Host ""
        }
        if ($rawTags) {
            Write-Host ("--- Tags: {0} ---" -f $rawTags) -ForegroundColor Gray
            Write-Host ""
        }
        if ($null -ne $storyPoints) {
            Write-Host ("--- Story Points: {0} ---" -f $storyPoints) -ForegroundColor Gray
            Write-Host ""
        }
    }

    $result = [PSCustomObject]@{
        success       = $true
        pbiId         = $pbiId
        fieldsUpdated = @($fieldsToUpdate)
        commentPosted = $false
        dryRun        = $true
        message       = "Dry run complete. Use without -DryRun to push changes."
    }

    if ($Json) { $result | ConvertTo-Json -Depth 5 }
    exit 0
}

# ---------------------------------------------------------------------------
# Push to ADO
# ---------------------------------------------------------------------------

if (-not $Json) {
    Write-Host ("Updating AB#{0} in Azure DevOps..." -f $pbiId) -ForegroundColor Cyan
}

$updateParams = @{
    Organization = $org
    ProjectName  = $project
    PatToken     = $patToken
    PbiId        = $pbiId
}
if ($adoDescription)       { $updateParams['Description']         = $adoDescription }
if ($adoAC)                { $updateParams['AcceptanceCriteria']  = $adoAC }
if ($rawTags)              { $updateParams['Tags']                = $rawTags }
if ($null -ne $storyPoints){ $updateParams['StoryPoints']         = $storyPoints }

Update-AzureDevOpsPBI @updateParams | Out-Null

if (-not $Json) {
    Write-Host ("  Fields updated: {0}" -f ($fieldsToUpdate -join ', ')) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Post comment
# ---------------------------------------------------------------------------

$branchName = ""
try {
    $branchName = (git -C $specKitRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
}
catch { }

$commentLines = @(
    "<b>Refined by spec-kit on $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC</b><br/>"
    "Branch: <code>$branchName</code><br/>"
    "Fields updated: $($fieldsToUpdate -join ', ')<br/>"
    "<br/>"
    "Spec: <code>$specPath</code>"
)
$commentText = $commentLines -join ""

$commentPosted = $false
try {
    Add-AzureDevOpsPBIComment -Organization $org -ProjectName $project -PatToken $patToken -PbiId $pbiId -CommentText $commentText | Out-Null
    $commentPosted = $true
    if (-not $Json) {
        Write-Host "  Comment posted to work item." -ForegroundColor Green
    }
}
catch {
    if (-not $Json) {
        Write-Warning "Update succeeded but failed to post comment: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

$result = [PSCustomObject]@{
    success       = $true
    pbiId         = $pbiId
    fieldsUpdated = @($fieldsToUpdate)
    commentPosted = $commentPosted
    dryRun        = $false
    message       = "AB#$pbiId updated successfully."
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Host ""
    Write-Host ("AB#{0} updated successfully in Azure DevOps." -f $pbiId) -ForegroundColor Green
}
