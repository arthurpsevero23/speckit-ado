#!/usr/bin/env pwsh
<#
.SYNOPSIS
Create a new feature branch following GitFlow conventions with Azure DevOps PBI integration

.DESCRIPTION
Creates feature/bugfix/refactor branches following GitFlow naming:
  feature/<pbi-id>-short-description
  bugfix/<pbi-id>-short-description
  refactor/<pbi-id>-short-description
  cr_<number>/<pbi-id>-short-description

.PARAMETER PbiId
The Azure DevOps PBI work item ID

.PARAMETER WorkType
Type of work: feature, bugfix, refactor, or cr_<number>
Default: feature

.PARAMETER Description
Short description for the branch name

.PARAMETER Browse
Open the PBI in Azure DevOps after creating the branch

.EXAMPLE
# Create feature branch and select PBI interactively
./create-feature-from-pbi.ps1

# Create bugfix branch for specific PBI
./create-feature-from-pbi.ps1 -PbiId 1234 -WorkType bugfix -Description "remove-credentials"

# Create CR branch
./create-feature-from-pbi.ps1 -PbiId 5678 -WorkType cr_42
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [int]$PbiId = 0,
    
    [Parameter()]
    [ValidateSet('feature', 'bugfix', 'refactor')]
    [string]$WorkType = 'feature',
    
    [Parameter()]
    [string]$Description,
    
    [switch]$Browse,
    
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Show help
if ($Help) {
    Write-Host "Create a new feature branch with GitFlow naming and PBI integration"
    Write-Host ""
    Write-Host "Usage: ./create-feature-from-pbi.ps1 [-PbiId <id>] [-WorkType <type>] [-Description <desc>] [-Browse]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -PbiId <id>         Azure DevOps PBI work item ID"
    Write-Host "  -WorkType <type>    Type: feature (default), bugfix, refactor, or cr_<number>"
    Write-Host "  -Description <desc> Short description (optional, uses PBI title if not provided)"
    Write-Host "  -Browse             Open PBI in Azure DevOps after creating branch"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ./create-feature-from-pbi.ps1                           # Interactive selection"
    Write-Host "  ./create-feature-from-pbi.ps1 -PbiId 1234 -WorkType bugfix"
    Write-Host "  ./create-feature-from-pbi.ps1 -PbiId 5678 -Description 'auth-cleanup'"
    exit 0
}

# Find spec-kit root
$currentDir = Get-Location
if ($currentDir -isnot [System.IO.DirectoryInfo]) {
    $currentDir = Get-Item $currentDir
}

$dir = $currentDir
$specKitRoot = $null
while ($dir) {
    $testPath = Join-Path $dir '.specify'
    if (Test-Path $testPath) {
        $specKitRoot = $dir
        break
    }
    $dir = $dir.Parent
    if (-not $dir) { break }
}

if (-not $specKitRoot) {
    Write-Error "Cannot find .specify folder. Are you in a spec-kit workspace?"
    exit 1
}

Set-Location $specKitRoot

# Load config and module
$initOptionsPath = Join-Path $specKitRoot '.specify\init-options.json'
$modulePath = Join-Path $specKitRoot '.specify\modules\azure-devops-integration.ps1'

$config = Get-Content $initOptionsPath -Raw | ConvertFrom-Json
$ado = $config.ado

if (-not $ado.enabled) {
    Write-Error "Azure DevOps integration is not enabled"
    Write-Error "Enable it in: .specify/init-options.json"
    exit 1
}

. $modulePath

# Get credentials
$patToken = [Environment]::GetEnvironmentVariable($ado.patTokenEnvVar)
if (-not $patToken) {
    Write-Error "PAT token not found in environment variable: $($ado.patTokenEnvVar)"
    exit 1
}

# Fetch PBIs
Write-Host "Fetching PBIs from Azure DevOps..." -ForegroundColor Cyan

$pbis = Get-AzureDevOpsPBIs -Organization $ado.organization `
                             -ProjectName $ado.projectName `
                             -PatToken $patToken `
                             -FilterByState $ado.filterByState `
                             -FilterByIteration $ado.filterByIteration

if ($pbis.Count -eq 0) {
    Write-Error "No PBIs found matching filter criteria"
    exit 1
}

# If PBI ID not provided, show interactive selection
if ($PbiId -eq 0) {
    Write-Host ""
    Write-Host "Select a PBI:" -ForegroundColor Green
    for ($i = 0; $i -lt $pbis.Count; $i++) {
        $pbi = $pbis[$i]
        Write-Host "  [$($i + 1)] AB#$($pbi.Id) - $($pbi.Title) [$($pbi.State)]"
    }
    Write-Host ""
    
    $selection = Read-Host "Enter number (1-$($pbis.Count))" 
    $selectedIndex = -1
    if ([int]::TryParse($selection, [ref]$selectedIndex)) {
        $selectedIndex = $selectedIndex - 1
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $pbis.Count) {
            $pbi = $pbis[$selectedIndex]
            $PbiId = $pbi.Id
        } else {
            Write-Error "Invalid selection"
            exit 1
        }
    } else {
        Write-Error "Invalid input"
        exit 1
    }
} else {
    # Find the selected PBI
    $pbi = $pbis | Where-Object { $_.Id -eq $PbiId }
    if (-not $pbi) {
        Write-Error "PBI #$PbiId not found in fetched results"
        exit 1
    }
}

# Display selected PBI
Write-Host ""
Write-Host "Selected PBI:" -ForegroundColor Green
Write-Host "  ID: AB#$($pbi.Id)"
Write-Host "  Title: $($pbi.Title)"
Write-Host "  State: $($pbi.State)"
Write-Host ""

# Generate branch name
function ConvertTo-CleanBranchName {
    param([string]$Name)
    $name = $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
    return $name -replace '--+', '-'
}

if ($Description) {
    $suffix = ConvertTo-CleanBranchName $Description
} else {
    # Use first 3-4 words from PBI title
    $titleWords = $pbi.Title.ToLower() -split '\s+' | Where-Object { $_ } | Select-Object -First 4
    $suffix = ($titleWords -join '-') -replace '[^a-z0-9-]', ''
}

$branchName = "$WorkType/$($pbi.Id)-$suffix"

# Validate branch name length (GitHub limit is 244 bytes)
if ($branchName.Length -gt 244) {
    $maxLen = 244 - $WorkType.Length - 1 - $pbi.Id.ToString().Length - 2
    $suffix = $suffix.Substring(0, $maxLen) -replace '-$', ''
    $branchName = "$WorkType/$($pbi.Id)-$suffix"
}

Write-Host "Creating branch: $branchName" -ForegroundColor Cyan

# Check if git is available
$hasGit = $false
try {
    $gitVersion = git --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hasGit = $true
    }
} catch { }

if ($hasGit) {
    # Determine base branch
    $baseBranch = 'develop'
    if ((git branch -r | grep -i 'origin/develop' 2>$null)) {
        $baseBranch = 'origin/develop'
    } elseif ((git branch -r | grep -i 'origin/main' 2>$null)) {
        $baseBranch = 'origin/main'
    }
    
    try {
        # Create branch from develop (or main if develop doesn't exist)
        git fetch origin 2>$null | Out-Null
        git checkout -b $branchName $baseBranch 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Branch created successfully" -ForegroundColor Green
        } else {
            Write-Error "Failed to create branch"
            exit 1
        }
    } catch {
        Write-Error "Git error: $_"
        exit 1
    }
} else {
    Write-Warning "Git not available; skipping branch creation"
}

# Create feature directory structure
$specsDir = Join-Path $specKitRoot 'specs'
$featureDir = Join-Path $specsDir $branchName
New-Item -ItemType Directory -Path $featureDir -Force | Out-Null

# Copy template
$templatePath = Join-Path $specKitRoot '.specify\templates\spec-template.md'
$specFile = Join-Path $featureDir 'spec.md'
if (Test-Path $templatePath) {
    Copy-Item $templatePath $specFile -Force
} else {
    New-Item -ItemType File -Path $specFile | Out-Null
}

# Set environment variable
$env:SPECIFY_FEATURE = $branchName
$env:SPECIFY_PBI = $pbi.Id

Write-Host ""
Write-Host "=== Feature Created ===" -ForegroundColor Cyan
Write-Host "Branch: $branchName"
Write-Host "PBI: AB#$($pbi.Id)"
Write-Host "Title: $($pbi.Title)"
Write-Host "Spec file: $specFile"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Edit the spec: $specFile"
Write-Host "  2. Run: /plan"
Write-Host "  3. Run: /tasks"
Write-Host ""

if ($Browse) {
    $pbiUrl = "https://dev.azure.com/$($ado.organization)/$($ado.projectName)/_workitems/edit/$($pbi.Id)"
    Write-Host "Opening: $pbiUrl" -ForegroundColor Cyan
    Start-Process $pbiUrl
}
