#!/usr/bin/env pwsh

[CmdletBinding()]
param(
    [switch]$SkipAdoSetup,
    [switch]$SkipDeepTest
)

$ErrorActionPreference = 'Stop'

function Get-PowerShellExecutable {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return 'pwsh'
    }

    return 'powershell'
}

function Add-Result {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$Name,
        [string]$Status,
        [string]$Details = ''
    )

    $Results.Add([PSCustomObject]@{
        Name = $Name
        Status = $Status
        Details = $Details
    })
}

function Test-CommandOutputContains {
    param(
        [string]$Command,
        [string]$ExpectedText
    )

    $output = Invoke-Expression $Command | Out-String
    if ($output -notmatch [regex]::Escape($ExpectedText)) {
        throw "Expected output to contain: $ExpectedText"
    }

    return $output.Trim()
}

$results = [System.Collections.Generic.List[object]]::new()
$shellExe = Get-PowerShellExecutable

Write-Host '=== spec-kit Consumer Install Validation ===' -ForegroundColor Cyan

try {
    $hasInstalledPackage = Test-Path 'node_modules/@arthurpsevero23/spec-kit'
    $hasLocalPackageSource = Test-Path 'package.json'

    if (-not $hasInstalledPackage -and -not $hasLocalPackageSource) {
        throw 'Neither installed package folder nor local package source was found.'
    }

    $details = if ($hasInstalledPackage) { 'Detected node_modules installation' } else { 'Detected local package source repository' }
    Add-Result -Results $results -Name 'Package installed' -Status 'PASS' -Details $details
}
catch {
    Add-Result -Results $results -Name 'Package installed' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    if ((Test-Path 'node_modules/@arthurpsevero23/spec-kit/bin/spec-kit.js') -or (Test-Path 'bin/spec-kit.js')) {
        $details = if (Test-Path 'node_modules/@arthurpsevero23/spec-kit/bin/spec-kit.js') { 'Using installed package CLI' } else { 'Using local source CLI' }
        Add-Result -Results $results -Name 'CLI entrypoint present' -Status 'PASS' -Details $details
    }
    else {
        throw 'CLI entrypoint not found in node_modules or local bin/'
    }
}
catch {
    Add-Result -Results $results -Name 'CLI entrypoint present' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    Test-CommandOutputContains -Command 'npx spec-kit --help' -ExpectedText 'spec-kit CLI' | Out-Null
    Add-Result -Results $results -Name 'CLI help' -Status 'PASS'
}
catch {
    Add-Result -Results $results -Name 'CLI help' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    $versionOutput = Test-CommandOutputContains -Command 'npx spec-kit --version' -ExpectedText '0.5.1'
    Add-Result -Results $results -Name 'CLI version' -Status 'PASS' -Details $versionOutput
}
catch {
    Add-Result -Results $results -Name 'CLI version' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    if (-not (Test-Path '.specify')) {
        & npx spec-kit init | Out-Null
    }

    foreach ($path in @('.specify', '.setup-spec-kit.ps1')) {
        if (-not (Test-Path $path)) {
            throw "Required initialized path not found: $path"
        }
    }

    Add-Result -Results $results -Name 'Project initialized' -Status 'PASS'
}
catch {
    Add-Result -Results $results -Name 'Project initialized' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    $requiredPaths = @(
        '.specify/init-options.json',
        '.specify/scripts/setup-ado.ps1',
        '.specify/scripts/powershell/test-functionality.ps1',
        '.specify/scripts/powershell/create-pbi-for-specify.ps1',
        '.specify/scripts/powershell/select-pbi-for-specify.ps1',
        '.specify/scripts/powershell/push-pbi-refinements.ps1',
        '.specify/scripts/powershell/deep-test-ado-workflow.ps1'
    )

    foreach ($path in $requiredPaths) {
        if (-not (Test-Path $path)) {
            throw "Missing required path: $path"
        }
    }

    Add-Result -Results $results -Name 'Packaged files present' -Status 'PASS'
}
catch {
    Add-Result -Results $results -Name 'Packaged files present' -Status 'FAIL' -Details $_.Exception.Message
}

try {
    & $shellExe -NoProfile -ExecutionPolicy Bypass -File '.\.specify\scripts\powershell\test-functionality.ps1' | Out-Null
    Add-Result -Results $results -Name 'Functionality smoke test' -Status 'PASS'
}
catch {
    Add-Result -Results $results -Name 'Functionality smoke test' -Status 'FAIL' -Details $_.Exception.Message
}

if (-not $SkipDeepTest) {
    try {
        & $shellExe -NoProfile -ExecutionPolicy Bypass -File '.\.specify\scripts\powershell\deep-test-ado-workflow.ps1' -DryRunOnly | Out-Null
        Add-Result -Results $results -Name 'Deep ADO dry-run test' -Status 'PASS'
    }
    catch {
        Add-Result -Results $results -Name 'Deep ADO dry-run test' -Status 'FAIL' -Details $_.Exception.Message
    }
}
else {
    Add-Result -Results $results -Name 'Deep ADO dry-run test' -Status 'SKIP' -Details 'Skipped by parameter'
}

if (-not $SkipAdoSetup) {
    try {
        if (-not (Test-Path '.specify/init-options.json')) {
            throw 'init-options.json not found for ADO setup validation'
        }

        $config = Get-Content '.specify/init-options.json' -Raw | ConvertFrom-Json
        $requiredAdoFields = @('enabled', 'organization', 'projectName', 'patTokenEnvVar')
        foreach ($field in $requiredAdoFields) {
            if (-not $config.ado.PSObject.Properties.Name.Contains($field)) {
                throw "Missing ado field: $field"
            }
        }

        Add-Result -Results $results -Name 'ADO config schema present' -Status 'PASS'
    }
    catch {
        Add-Result -Results $results -Name 'ADO config schema present' -Status 'FAIL' -Details $_.Exception.Message
    }
}
else {
    Add-Result -Results $results -Name 'ADO config schema present' -Status 'SKIP' -Details 'Skipped by parameter'
}

Write-Host ''
Write-Host 'Results:' -ForegroundColor Cyan
foreach ($result in $results) {
    $color = if ($result.Status -eq 'PASS') { 'Green' } elseif ($result.Status -eq 'SKIP') { 'Yellow' } else { 'Red' }
    Write-Host ("[{0}] {1}" -f $result.Status, $result.Name) -ForegroundColor $color
    if ($result.Details) {
        Write-Host ("  {0}" -f $result.Details) -ForegroundColor Gray
    }
}

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
Write-Host ''
Write-Host ("Summary: {0} passed, {1} failed, {2} skipped" -f @($results | Where-Object { $_.Status -eq 'PASS' }).Count, $failed, @($results | Where-Object { $_.Status -eq 'SKIP' }).Count)

exit $(if ($failed -gt 0) { 1 } else { 0 })