# Simple test suite for spec-kit functionality
# ASCII-only version - no Unicode characters

$ErrorActionPreference = "Continue"
$tests = @()

Write-Host ""
Write-Host "========================================================"
Write-Host "  SPEC-KIT TEST SUITE"
Write-Host "========================================================"
Write-Host ""

# TEST 1: Configuration
Write-Host "TEST 1: Configuration Loading"
Write-Host "========================================================" -ForegroundColor Yellow

$cfgPath = ".\.specify\init-options.json"
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath | ConvertFrom-Json
    Write-Host "[PASS] Config loaded" -ForegroundColor Green
    Write-Host "  - Organization: $($cfg.ado.organization)"
    Write-Host "  - Project: $($cfg.ado.projectName)"
    Write-Host "  - ADO Enabled: $($cfg.ado.enabled)"
    $tests += "Config:PASS"
} else {
    Write-Host "[FAIL] Config not found" -ForegroundColor Red
    $tests += "Config:FAIL"
}

Write-Host ""

# TEST 2: Module Loading
Write-Host "TEST 2: Module Loading"
Write-Host "========================================================" -ForegroundColor Yellow

$modPath = ".\.specify\modules\azure-devops-integration.ps1"
if (Test-Path $modPath) {
    . $modPath
    Write-Host "[PASS] Module loaded" -ForegroundColor Green
    
    if (Get-Command Get-LevenshteinDistance -ErrorAction SilentlyContinue) {
        Write-Host "  - Get-LevenshteinDistance: Available"
    } else {
        Write-Host "  - Get-LevenshteinDistance: Not found" -ForegroundColor Yellow
    }
    
    $tests += "Module:PASS"
} else {
    Write-Host "[FAIL] Module not found" -ForegroundColor Red
    $tests += "Module:FAIL"
}

Write-Host ""

# TEST 3: Fuzzy Matching
Write-Host "TEST 3: Levenshtein Distance Function"
Write-Host "========================================================" -ForegroundColor Yellow

try {
    $d1 = Get-LevenshteinDistance -String1 "hello" -String2 "hello"
    $d2 = Get-LevenshteinDistance -String1 "hello" -String2 "hallo"
    $d3 = Get-LevenshteinDistance -String1 "test" -String2 "tests"
    
    Write-Host "[PASS] Levenshtein distance working" -ForegroundColor Green
    Write-Host "  - Distance('hello', 'hello') = $d1"
    Write-Host "  - Distance('hello', 'hallo') = $d2"
    Write-Host "  - Distance('test', 'tests') = $d3"
    
    if ($d1 -eq 0 -and $d2 -eq 1 -and $d3 -eq 1) {
        Write-Host "[PASS] Results are correct" -ForegroundColor Green
        $tests += "Fuzzy:PASS"
    } else {
        Write-Host "[FAIL] Unexpected results" -ForegroundColor Red
        $tests += "Fuzzy:FAIL"
    }
} catch {
    Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
    $tests += "Fuzzy:FAIL"
}

Write-Host ""

# TEST 4: Hook Files
Write-Host "TEST 4: Hook File Structure"
Write-Host "========================================================" -ForegroundColor Yellow

$files = @(
    ".\.specify\hooks\after_tasks.ps1",
    ".\.specify\extensions.yml",
    ".\.specify\scripts\setup-ado.ps1",
    ".\.specify\scripts\powershell\select-pbi-for-specify.ps1",
    ".\.specify\scripts\powershell\create-pbi-for-specify.ps1",
    ".\.specify\scripts\powershell\deep-test-ado-workflow.ps1",
    ".\.github\agents\speckit.create-pbi.agent.md",
    ".\.github\prompts\speckit.create-pbi.prompt.md",
    ".\.specify\docs\WORKFLOW_GUIDE.md",
    ".\.specify\docs\POWERSHELL_SCRIPTS.md"
)

$allOk = $true
foreach ($f in $files) {
    if (Test-Path $f) {
        Write-Host "[OK] $f" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $f" -ForegroundColor Red
        $allOk = $false
    }
}

if ($allOk) {
    Write-Host "[PASS] All hook files present" -ForegroundColor Green
    $tests += "Hooks:PASS"
} else {
    $tests += "Hooks:FAIL"
}

Write-Host ""

# SUMMARY
Write-Host "========================================================"
Write-Host "TEST SUMMARY"
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

$pass = @($tests | Where-Object { $_ -match "PASS" }).Count
$fail = @($tests | Where-Object { $_ -match "FAIL" }).Count

foreach ($t in $tests) {
    $result = $t.Split(":")[0]
    $status = $t.Split(":")[1]
    $col = if ($status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  $status - $result" -ForegroundColor $col
}

Write-Host ""
Write-Host "Results: $pass passed, $fail failed"
Write-Host ""

exit $(if ($fail -gt 0) { 1 } else { 0 })
