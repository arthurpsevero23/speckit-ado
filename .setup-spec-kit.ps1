# Installation template for other repositories
# This script should be run in other repos to set up @arthurpsevero23/spec-kit
# Usage: powershell -ExecutionPolicy Bypass -File .\node_modules\@arthurpsevero23\spec-kit\.setup-spec-kit.ps1

param(
    [switch]$SkipNpmInstall,
    [switch]$SkipInteractiveSetup
)

$ErrorActionPreference = "Stop"

# Resolve the consumer project root (the directory where this script was invoked from)
$projectRoot = (Get-Location).Path

if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $psExe = "pwsh"
} else {
    $psExe = "powershell"
}


Write-Host "================================" -ForegroundColor Cyan
Write-Host "@arthurpsevero23/spec-kit Setup" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify npm is installed
Write-Host "[1/5] Verifying npm installation..." -ForegroundColor Yellow
try {
    $npmVersion = npm --version
    Write-Host "[OK] npm v$npmVersion found" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] npm not found. Please install Node.js/npm first." -ForegroundColor Red
    exit 1
}

# Step 2: Install package
Write-Host ""
Write-Host "[2/5] Installing @arthurpsevero23/spec-kit..." -ForegroundColor Yellow
if (-not $SkipNpmInstall) {
    npm install @arthurpsevero23/spec-kit
    Write-Host "[OK] Package installed" -ForegroundColor Green
}
else {
    Write-Host "[-] Skipping npm install (--SkipNpmInstall)" -ForegroundColor Yellow
}

# Step 3: Run spec-kit init (copies .specify, .github/agents, .github/prompts to project root)
Write-Host ""
Write-Host "[3/5] Running spec-kit init..." -ForegroundColor Yellow
try {
    npx spec-kit init
    Write-Host "[OK] spec-kit init completed" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] spec-kit init failed: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Create project-specific init-options.json template
Write-Host ""
Write-Host "[4/5] Creating local configuration template..." -ForegroundColor Yellow

$speckitVersion = (Get-Content (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json).version

$localConfigContent = @"
{
  "speckit_version": "$speckitVersion",
  "stages": {
    "specify": {
      "engine": "claude",
      "rules": "Use technical but clear language. Focus on requirements and constraints."
    },
    "plan": {
      "engine": "claude",
      "rules": "Create actionable implementation steps with accurate time estimates."
    },
    "tasks": {
      "engine": "claude",
      "rules": "Generate specific, verifiable, independently completable tasks."
    }
  },
  "ado": {
    "enabled": true,
    "organization": "arthurpsevero23",
    "projectName": "your-project-name",
    "patTokenEnvVar": "ADO_PAT_TOKEN",
    "filterByState": ["Active", "Committed"],
    "filterByIteration": null,
    "taskIdFormat": "AB#"
  },
  "gitflow": {
    "enabled": true,
    "mainBranch": "main",
    "developBranch": "develop",
    "featureBranch": "feature",
    "bugfixBranch": "bugfix",
    "refactorBranch": "refactor"
  }
}
"@

# Check if config exists in node_modules
$nodeModulesInitPath = Join-Path $projectRoot 'node_modules/@arthurpsevero23/spec-kit/.specify/init-options.json'
if (Test-Path $nodeModulesInitPath) {
    Write-Host "[OK] Template found in npm package" -ForegroundColor Green
    Write-Host "  Location: $nodeModulesInitPath" -ForegroundColor Gray
}
else {
    Write-Host "[-] Template not found in expected location" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Template configuration:" -ForegroundColor Cyan
Write-Host $localConfigContent | Out-String

# Step 5: Provide next steps
Write-Host ""
Write-Host "[5/5] Setup Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Create/update .specify/init-options.json with:" -ForegroundColor White
Write-Host "   - Your Azure DevOps organization name" -ForegroundColor Gray
Write-Host "   - Your Azure DevOps project name" -ForegroundColor Gray
Write-Host "   - Set ADO_PAT_TOKEN environment variable" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Run interactive setup:" -ForegroundColor White
Write-Host "   $psExe -NoProfile -ExecutionPolicy Bypass ./.specify/scripts/setup-ado.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Create your first feature from a PBI:" -ForegroundColor White
Write-Host "   $psExe -NoProfile -ExecutionPolicy Bypass ./.specify/scripts/powershell/create-feature-from-pbi.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Use /speckit.specify in VS Code Copilot Chat" -ForegroundColor White
Write-Host ""

# Step 6: Optional interactive setup
if (-not $SkipInteractiveSetup) {
    Write-Host ""
    $response = Read-Host "Would you like to run the interactive ADO setup now? (y/n)"
    if ($response -eq "y" -or $response -eq "Y") {
        $setupScript = Join-Path $projectRoot '.specify/scripts/setup-ado.ps1'
        if (Test-Path $setupScript) {
            Write-Host ""
            Write-Host "Starting interactive setup..." -ForegroundColor Cyan
            Write-Host ""
            & $setupScript
        }
        else {
            Write-Host "[FAIL] Setup script not found at: $setupScript" -ForegroundColor Red
            Write-Host "  Try running setup from the npm package location" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - Azure DevOps Setup: node_modules/@arthurpsevero23/spec-kit/.specify/docs/AZURE_DEVOPS_SETUP.md" -ForegroundColor Gray
Write-Host "  - GitFlow Workflow: node_modules/@arthurpsevero23/spec-kit/.specify/docs/GITFLOW_SETUP.md" -ForegroundColor Gray

Write-Host ""
