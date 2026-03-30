#!/usr/bin/env pwsh
<#
.SYNOPSIS
Select a backlog PBI and prepare context for /speckit.specify.

.DESCRIPTION
Supports two modes:
1) Direct fast path by PBI ID
2) Interactive fallback with optional filters
   - state
   - sprint/iteration
   - assignee
   - text search in title

After selection, this script stores context in:
  .specify/context/selected-pbi.json

Then the user can run /speckit.specify and the agent will include this PBI context.

.EXAMPLE
./select-pbi-for-specify.ps1 -PbiId 1234

.EXAMPLE
./select-pbi-for-specify.ps1 -State Active,Committed -Sprint "Team\\Sprint 5" -AssignedTo "Arthur" -SearchText "auth"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$PbiId = 0,

    [Parameter()]
    [string[]]$State,

    [Parameter()]
    [string]$Sprint = "",

    [Parameter()]
    [string]$AssignedTo = "",

    [Parameter()]
    [string]$SearchText = "",

    [Parameter()]
    [int]$Top = 50,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Select a PBI and prepare /speckit.specify context"
    Write-Host ""
    Write-Host "Usage: ./select-pbi-for-specify.ps1 [-PbiId <id>] [-State <states>] [-Sprint <iteration>] [-AssignedTo <name>] [-SearchText <text>] [-Top <n>]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ./select-pbi-for-specify.ps1 -PbiId 1234"
    Write-Host "  ./select-pbi-for-specify.ps1 -State Active,Committed -SearchText auth"
    exit 0
}

function Find-SpecKitRoot {
    $currentDir = Get-Location
    if ($currentDir -isnot [System.IO.DirectoryInfo]) {
        $currentDir = Get-Item $currentDir
    }

    $dir = $currentDir
    while ($dir) {
        $testPath = Join-Path $dir '.specify'
        if (Test-Path $testPath) {
            return $dir
        }
        $dir = $dir.Parent
        if (-not $dir) { break }
    }

    return $null
}

function Select-PBIFromList {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$PBIs
    )

    Write-Host ""
    Write-Host "Select a PBI:" -ForegroundColor Green

    for ($i = 0; $i -lt $PBIs.Count; $i++) {
        $pbi = $PBIs[$i]
        $assignee = if ($pbi.AssignedTo) { $pbi.AssignedTo } else { 'Unassigned' }
        $iteration = if ($pbi.Iteration) { $pbi.Iteration } else { 'No Iteration' }
        Write-Host ("  [{0}] AB#{1} - {2} [{3}] | {4} | {5}" -f ($i + 1), $pbi.Id, $pbi.Title, $pbi.State, $assignee, $iteration)
    }

    Write-Host ""
    $selection = Read-Host "Enter number (1-$($PBIs.Count))"
    $selectedIndex = 0

    if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
        throw "Invalid input: '$selection'"
    }

    $selectedIndex = $selectedIndex - 1
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $PBIs.Count) {
        throw "Invalid selection number: $selection"
    }

    return $PBIs[$selectedIndex]
}

$specKitRoot = Find-SpecKitRoot
if (-not $specKitRoot) {
    Write-Error "Cannot find .specify folder. Are you in a spec-kit workspace?"
    exit 1
}

Set-Location $specKitRoot

$initOptionsPath = Join-Path $specKitRoot '.specify\init-options.json'
$modulePath = Join-Path $specKitRoot '.specify\modules\azure-devops-integration.ps1'
$contextDir = Join-Path $specKitRoot '.specify\context'
$contextPath = Join-Path $contextDir 'selected-pbi.json'

if (-not (Test-Path $initOptionsPath)) {
    Write-Error "Missing file: $initOptionsPath"
    exit 1
}

if (-not (Test-Path $modulePath)) {
    Write-Error "Missing file: $modulePath"
    exit 1
}

$config = Get-Content $initOptionsPath -Raw | ConvertFrom-Json
if (-not $config.ado -or -not $config.ado.enabled) {
    Write-Error "Azure DevOps integration is not enabled in .specify/init-options.json"
    exit 1
}

if ($config.ado.specifySelection -and $config.ado.specifySelection.persistContextPath) {
    $relativePath = [string]$config.ado.specifySelection.persistContextPath
    if ($relativePath) {
        $contextPath = Join-Path $specKitRoot $relativePath
        $contextDir = Split-Path -Parent $contextPath
    }
}

. $modulePath

$patToken = [Environment]::GetEnvironmentVariable($config.ado.patTokenEnvVar)
if (-not $patToken) {
    Write-Error "PAT token not found in environment variable: $($config.ado.patTokenEnvVar)"
    exit 1
}

$selectedPbi = $null

if ($PbiId -gt 0) {
    Write-Host "Fetching PBI AB#$PbiId..." -ForegroundColor Cyan
    $selectedPbi = Get-AzureDevOpsPBIDetails -Organization $config.ado.organization -ProjectName $config.ado.projectName -PatToken $patToken -PbiId $PbiId

    if (-not $selectedPbi) {
        Write-Error "PBI AB#$PbiId not found"
        exit 1
    }
}
else {
    if ($PSBoundParameters.ContainsKey('Top') -eq $false -and $config.ado.specifySelection -and $config.ado.specifySelection.defaultTop) {
        $Top = [int]$config.ado.specifySelection.defaultTop
    }

    $effectiveStates = @()
    if ($State -and $State.Count -gt 0) {
        $effectiveStates = $State
    }
    elseif ($config.ado.filterByState) {
        $effectiveStates = @($config.ado.filterByState)
    }
    else {
        $effectiveStates = @('Active', 'Committed')
    }

    $effectiveSprint = if ($Sprint) { $Sprint } else { [string]$config.ado.filterByIteration }

    Write-Host "Searching PBIs..." -ForegroundColor Cyan
    Write-Host ("  States: {0}" -f ($effectiveStates -join ', ')) -ForegroundColor Gray
    Write-Host ("  Sprint: {0}" -f $(if ($effectiveSprint) { $effectiveSprint } else { 'Any' })) -ForegroundColor Gray
    Write-Host ("  Assigned To: {0}" -f $(if ($AssignedTo) { $AssignedTo } else { 'Any' })) -ForegroundColor Gray
    Write-Host ("  Text Search: {0}" -f $(if ($SearchText) { $SearchText } else { 'Any' })) -ForegroundColor Gray

    $pbis = Get-AzureDevOpsPBIs -Organization $config.ado.organization `
                                -ProjectName $config.ado.projectName `
                                -PatToken $patToken `
                                -FilterByState $effectiveStates `
                                -FilterByIteration $effectiveSprint `
                                -FilterByAssignedTo $AssignedTo `
                                -SearchText $SearchText `
                                -Top $Top

    if (-not $pbis -or $pbis.Count -eq 0) {
        Write-Error "No PBIs found with the provided filters"
        exit 1
    }

    $selectedPbi = Select-PBIFromList -PBIs $pbis
}

if (-not (Test-Path $contextDir)) {
    New-Item -Path $contextDir -ItemType Directory -Force | Out-Null
}

$context = [PSCustomObject]@{
    selectedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    source = [PSCustomObject]@{
        organization = $config.ado.organization
        projectName = $config.ado.projectName
    }
    filters = [PSCustomObject]@{
        state = if ($State) { $State } else { $config.ado.filterByState }
        sprint = if ($Sprint) { $Sprint } else { $config.ado.filterByIteration }
        assignedTo = $AssignedTo
        searchText = $SearchText
    }
    pbi = [PSCustomObject]@{
        id = $selectedPbi.Id
        taskId = (ConvertTo-TaskId -PBIId $selectedPbi.Id)
        title = $selectedPbi.Title
        description = $selectedPbi.Description
        acceptanceCriteria = $selectedPbi.AcceptanceCriteria
        state = $selectedPbi.State
        assignedTo = $selectedPbi.AssignedTo
        iteration = $selectedPbi.Iteration
        tags = $selectedPbi.Tags
        storyPoints = $selectedPbi.StoryPoints
    }
}

$context | ConvertTo-Json -Depth 8 | Set-Content -Path $contextPath -Encoding UTF8

$env:SPECIFY_PBI = $selectedPbi.Id
$env:SPECIFY_PBI_ID = $selectedPbi.Id
$env:SPECIFY_PBI_TITLE = $selectedPbi.Title

Write-Host ""
Write-Host "PBI selected and context saved." -ForegroundColor Green
Write-Host ("  PBI: AB#{0} - {1}" -f $selectedPbi.Id, $selectedPbi.Title)
Write-Host ("  Context file: {0}" -f $contextPath)
Write-Host ""
Write-Host "Next step:" -ForegroundColor Cyan
Write-Host "  Run /speckit.specify with your feature description." -ForegroundColor Gray
Write-Host "  The selected PBI context will be included automatically." -ForegroundColor Gray
Write-Host ""
