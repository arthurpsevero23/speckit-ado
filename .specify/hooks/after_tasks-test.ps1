<#
.SYNOPSIS
Test hook to verify Azure DevOps integration infrastructure

.DESCRIPTION
Simple test hook to validate syntax and structure
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FeaturePath,
    
    [Parameter(Mandatory = $true)]
    [string]$SpecKitRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Azure DevOps Integration Hook - Test Mode" -ForegroundColor Cyan
Write-Host "FeaturePath: $FeaturePath" -ForegroundColor Gray
Write-Host "SpecKitRoot: $SpecKitRoot" -ForegroundColor Gray
