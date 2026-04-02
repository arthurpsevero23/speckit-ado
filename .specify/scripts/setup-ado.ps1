#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$false)]
    [switch]$Skip
)

# Azure DevOps Setup Wizard for Spec-Kit

$specKitRoot = Get-Location
if ($specKitRoot -isnot [System.IO.DirectoryInfo]) {
    $specKitRoot = Get-Item $specKitRoot
}

# Find .specify folder (limit to 3 levels up to avoid matching unrelated projects)
$dir = $specKitRoot
$found = $false
$maxDepth = 3
$depth = 0
while ($dir -and $depth -lt $maxDepth) {
    $testPath = Join-Path $dir '.specify'
    if (Test-Path $testPath) {
        $specKitRoot = $dir
        $found = $true
        break
    }
    $dir = $dir.Parent
    $depth++
    if (-not $dir) { break }
}

if (-not $found) {
    Write-Host "ERROR: Cannot find .specify folder" -ForegroundColor Red
    exit 1
}

$initOptionsPath = Join-Path $specKitRoot '.specify\init-options.json'
$config = Get-Content $initOptionsPath -Raw | ConvertFrom-Json
$ado = $config.ado

Write-Host ""
Write-Host "=== Azure DevOps Setup Wizard ===" -ForegroundColor Cyan
Write-Host ""

# Load config
$org = $ado.organization
$proj = $ado.projectName
$patVar = $ado.patTokenEnvVar

# Check for PAT token
$pat = [Environment]::GetEnvironmentVariable($patVar)
if (-not $pat) {
    Write-Host "WARNING: PAT token not found in environment variable '$patVar'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To get a token:" -ForegroundColor Cyan
    Write-Host "  1. Go to https://dev.azure.com/$org"
    Write-Host "  2. Click your profile icon (top right) -> Personal access tokens"
    Write-Host "  3. Click + New Token, scope: Work Items (Read)"
    Write-Host "  4. Copy the token and paste it below"
    Write-Host ""
    $secPat = Read-Host "Enter your ADO PAT token" -AsSecureString
    $pat = [System.Net.NetworkCredential]::new('', $secPat).Password
    if (-not $pat) {
        Write-Host "ERROR: No token entered. Exiting." -ForegroundColor Red
        exit 1
    }
    $saveChoice = Read-Host "Save token permanently to user environment? (Y/n)"
    if ($saveChoice -ne 'n' -and $saveChoice -ne 'N') {
        [Environment]::SetEnvironmentVariable($patVar, $pat, "User")
        $env:ADO_PAT_TOKEN = $pat
        Write-Host "OK: Token saved to user environment as '$patVar'" -ForegroundColor Green
    } else {
        $env:ADO_PAT_TOKEN = $pat
        Write-Host "OK: Token set for this session only" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "OK: PAT token found" -ForegroundColor Green
Write-Host ""

# Get current settings
Write-Host "Current Configuration:"
Write-Host "  Organization: $org"
Write-Host "  Project: $proj"
Write-Host "  Enabled: $($ado.enabled)"
Write-Host ""

# Ask for updates
$orgInput = Read-Host "Organization (current: $org)"
if ($orgInput) { $org = $orgInput }

$projInput = Read-Host "Project (current: $proj)"
if ($projInput) { $proj = $projInput }

$enableInput = Read-Host "Enable ADO integration? (Y/n)"
$enabled = $enableInput -ne 'n'

# Test connection
if ($org -and $proj -and $pat) {
    Write-Host ""
    Write-Host "Testing connection..." -ForegroundColor Cyan
    
    $url = "https://dev.azure.com/$org/$proj/_apis/wit/wiql?api-version=7.0"
    $headers = @{
        Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + $pat)))"
        "Content-Type" = "application/json"
    }
    $qry = "SELECT TOP 1 [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Product Backlog Item'"
    $body = @{ query = $qry } | ConvertTo-Json
    
    try {
        $result = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 5
        Write-Host "OK: Connected successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Connection failed" -ForegroundColor Red
        Write-Host "  Check organization, project, and PAT token" -ForegroundColor Yellow
        exit 1
    }
}

# Save configuration
Write-Host ""
Write-Host "Saving configuration..." -ForegroundColor Cyan

$config.ado.organization = $org
$config.ado.projectName = $proj
$config.ado.enabled = $enabled

$json = $config | ConvertTo-Json -Depth 10
Set-Content -Path $initOptionsPath -Value $json -Encoding UTF8

Write-Host "OK: Configuration saved" -ForegroundColor Green
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Create a feature: /specify"
Write-Host "  2. Plan it: /plan"
Write-Host "  3. Generate tasks: /tasks"
Write-Host ""
Write-Host "Tasks will be automatically enriched with PBI IDs!"
Write-Host ""
