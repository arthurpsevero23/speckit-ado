# Installation template for other repositories
# This script should be run in other repos to set up @arthurpsevero23/spec-kit
# Usage: pwsh -NoProfile -ExecutionPolicy Bypass -File .setup-spec-kit.ps1

param(
    [string]$SkipNpmInstall = $false,
    [string]$InteractiveSetup = $true
)

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "@arthurpsevero23/spec-kit Setup" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify npm is installed
Write-Host "[1/5] Verifying npm installation..." -ForegroundColor Yellow
try {
    $npmVersion = npm --version
    Write-Host "✓ npm v$npmVersion found" -ForegroundColor Green
}
catch {
    Write-Host "✗ npm not found. Please install Node.js/npm first." -ForegroundColor Red
    exit 1
}

# Step 2: Install package
Write-Host ""
Write-Host "[2/5] Installing @arthurpsevero23/spec-kit..." -ForegroundColor Yellow
if ($SkipNpmInstall -eq $false) {
    npm install @arthurpsevero23/spec-kit
    Write-Host "✓ Package installed" -ForegroundColor Green
}
else {
    Write-Host "⊘ Skipping npm install (--SkipNpmInstall)" -ForegroundColor Yellow
}

# Step 3: Create local .specify folder structure
Write-Host ""
Write-Host "[3/5] Setting up .specify folder structure..." -ForegroundColor Yellow
$specifyPath = ".specify"
$localInitPath = ".specify/init-options.json"

if (Test-Path $localInitPath) {
    Write-Host "⊘ Local init-options.json already exists - skipping" -ForegroundColor Yellow
}
else {
    Write-Host "⊘ Local init-options.json not found - you'll need to configure this" -ForegroundColor Yellow
    Write-Host "   Use 'npm list @arthurpsevero23/spec-kit' to find the installed location" -ForegroundColor Gray
}

# Step 4: Create project-specific init-options.json template
Write-Host ""
Write-Host "[4/5] Creating local configuration template..." -ForegroundColor Yellow

$localConfigContent = @'
{
  "speckit_version": "0.5.0",
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
'@

# Check if config exists in node_modules
$nodeModulesInitPath = "node_modules/@arthurpsevero23/spec-kit/.specify/init-options.json"
if (Test-Path $nodeModulesInitPath) {
    Write-Host "✓ Template found in npm package" -ForegroundColor Green
    Write-Host "  Location: $nodeModulesInitPath" -ForegroundColor Gray
}
else {
    Write-Host "⊘ Template not found in expected location" -ForegroundColor Yellow
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
Write-Host "1. Initialize your repo with spec-kit:" -ForegroundColor White
Write-Host "   npx spec-kit init" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Create a .specify/init-options.json in your repo with:" -ForegroundColor White
Write-Host "   - Your Azure DevOps organization name" -ForegroundColor Gray
Write-Host "   - Your Azure DevOps project name" -ForegroundColor Gray
Write-Host "   - Set ADO_PAT_TOKEN environment variable" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Run interactive setup:" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass ./.specify/scripts/setup-ado.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Create your first feature from a PBI:" -ForegroundColor White
Write-Host "   pwsh -NoProfile -ExecutionPolicy Bypass ./.specify/scripts/powershell/create-feature-from-pbi.ps1" -ForegroundColor Gray
Write-Host ""

# Step 6: Optional interactive setup
if ($InteractiveSetup -eq $true) {
    Write-Host ""
    $response = Read-Host "Would you like to run the interactive ADO setup now? (y/n)"
    if ($response -eq "y" -or $response -eq "Y") {
        $setupScript = "./.specify/scripts/setup-ado.ps1"
        if (Test-Path $setupScript) {
            Write-Host ""
            Write-Host "Starting interactive setup..." -ForegroundColor Cyan
            Write-Host ""
            & $setupScript
        }
        else {
            Write-Host "✗ Setup script not found at: $setupScript" -ForegroundColor Red
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
Write-Host "  - Azure DevOps Setup: node_modules/@arthurpsevero23/spec-kit/AZURE_DEVOPS_SETUP.md" -ForegroundColor Gray
Write-Host "  - GitFlow Workflow: node_modules/@arthurpsevero23/spec-kit/GITFLOW_SETUP.md" -ForegroundColor Gray
Write-Host "  - NPM Account Setup: node_modules/@arthurpsevero23/spec-kit/.specify/docs/NPM_ACCOUNT_SETUP.md" -ForegroundColor Gray
Write-Host ""
