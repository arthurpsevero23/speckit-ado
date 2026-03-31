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

# Find .specify folder
$dir = $specKitRoot
$found = $false
while ($dir) {
    $testPath = Join-Path $dir '.specify'
    if (Test-Path $testPath) {
        $specKitRoot = $dir
        $found = $true
        break
    }
    $dir = $dir.Parent
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
    Write-Host "WARNING: PAT token not found in $patVar" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To set up, run one of these:"
    Write-Host ""
    Write-Host "PowerShell:"
    Write-Host '  $env:ADO_PAT_TOKEN = "your-token-here"'
    Write-Host ""
    Write-Host "Or permanently:"
    Write-Host '  [Environment]::SetEnvironmentVariable("ADO_PAT_TOKEN", "your-token", "User")'
    Write-Host ""
    Write-Host "To get a token:"
    Write-Host "  1. Go to https://dev.azure.com/YOUR-ORG"
    Write-Host "  2. Click profile icon - Personal access tokens"
    Write-Host "  3. New Token with scope: Work Items (Read)"
    Write-Host "  4. Copy and set as environment variable above"
    Write-Host ""
    exit 0
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
