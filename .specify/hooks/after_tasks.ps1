<#
.SYNOPSIS
Spec-Kit hook that enriches tasks.md with Azure DevOps PBI IDs

.DESCRIPTION
This hook runs after task generation to replace sequential task IDs (T001, T002)
with Azure DevOps Product Backlog Item IDs (AB#1234).

Process:
1. Loads Azure DevOps configuration from init-options.json
2. Fetches PBIs from Azure DevOps API with state and iteration filtering
3. Matches task descriptions to PBI titles using fuzzy matching
4. Transforms task.md
5. Logs mapping results

.PARAMETER FeaturePath
Path to the feature directory containing tasks.md

.PARAMETER SpecKitRoot
Root of the spec-kit workspace (where .specify folder is located)

.EXAMPLE
. .\after_tasks.ps1 -FeaturePath "C:\project\specs\001-my-feature" -SpecKitRoot "C:\project"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FeaturePath,
    
    [Parameter(Mandatory = $true)]
    [string]$SpecKitRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Main() {
    Write-Host "`n=== Azure DevOps Task Enrichment Hook ===" -ForegroundColor Cyan
    
    $initOptionsPath = Join-Path $SpecKitRoot '.specify\init-options.json'
    $modulePath = Join-Path $SpecKitRoot '.specify\modules\azure-devops-integration.ps1'
    $tasksPath = Join-Path $FeaturePath 'tasks.md'
    
    # Validate required files
    foreach ($path in @($initOptionsPath, $modulePath, $tasksPath)) {
        if (-not (Test-Path $path)) {
            Write-Error "Required file not found: $path"
            return 1
        }
    }
    
    # Load module
    . $modulePath
    
    # Try to load configuration
    $config = $null
    try {
        $config = Get-AzureDevOpsConfig -InitOptionsPath $initOptionsPath
        Write-Host "[OK] Azure DevOps configuration loaded" -ForegroundColor Green
    }
    catch {
        Write-Warning "ADO integration skipped: $($_.Exception.Message)"
        Write-Host "     To enable, set ado.enabled=true in init-options.json" -ForegroundColor Yellow
        return 0
    }
    
    # Get PAT token
    $patToken = $null
    try {
        $patToken = Get-PATToken -Config $config
        Write-Host "[OK] PAT token retrieved from environment" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to get PAT token: $($_.Exception.Message)"
        return 1
    }
    
    # Fetch PBIs
    Write-Host "`nFetching PBIs from Azure DevOps..." -ForegroundColor Cyan
    $pbis = $null
    try {
        $pbis = Get-AzureDevOpsPBIs -Organization $config.organization `
                                     -ProjectName $config.projectName `
                                     -PatToken $patToken `
                                     -FilterByState $config.filterByState `
                                     -FilterByIteration $config.filterByIteration
        
        Write-Host "[OK] Retrieved $($pbis.Count) PBIs" -ForegroundColor Green
        
        if ($pbis.Count -eq 0) {
            Write-Warning "No PBIs found matching filter criteria"
            return 0
        }
    }
    catch {
        Write-Error "Failed to fetch PBIs: $($_.Exception.Message)"
        return 1
    }
    
    # Read tasks
    Write-Host "`nReading tasks from $tasksPath..." -ForegroundColor Cyan
    $taskLines = @(Get-Content $tasksPath)
    Write-Host "[OK] Read $($taskLines.Count) lines" -ForegroundColor Green
    
    # Parse and match tasks
    Write-Host "`nMatching tasks to PBIs..." -ForegroundColor Cyan
    
    $taskPattern = '^\s*-\s+\[[xX ]?\]\s+(\[T\d{3}\])\s+(.*?)(?:\s+in\s+.+)?$'
    $matchCount = 0
    $unmatchedCount = 0
    $newLines = @()
    $matchLog = @()
    
    foreach ($line in $taskLines) {
        if ($line -match $taskPattern) {
            $fullTaskId = $matches[1]
            $taskDescription = $matches[2]
            $cleanDescription = $taskDescription -replace '\[P\]', '' -replace '\s+', ' '
            
            $matchedPbi = Find-MatchingPBI -TaskDescription $cleanDescription -PBIs $pbis -SimilarityThreshold 70
            
            if ($matchedPbi) {
                $taskId = ConvertTo-TaskId -PBIId $matchedPbi.Id
                $newLine = $line -replace '\[T\d{3}\]', "[$taskId]"
                
                $newLines += $newLine
                $matchCount++
                $matchLog += @{
                    Old = $fullTaskId
                    New = "[$taskId]"
                    Description = $cleanDescription
                    PBITitle = $matchedPbi.Title
                    PBIState = $matchedPbi.State
                }
                
                Write-Host "  [$matchCount] MATCH: $fullTaskId -> [$taskId]" -ForegroundColor Green
            }
            else {
                $newLines += $line
                $unmatchedCount++
                Write-Host "  ! SKIP: $fullTaskId (no match)" -ForegroundColor Yellow
            }
        }
        else {
            $newLines += $line
        }
    }
    
    # Write updated tasks
    Write-Host "`nUpdating tasks.md..." -ForegroundColor Cyan
    Set-Content -Path $tasksPath -Value $newLines -Encoding UTF8
    Write-Host "[OK] Updated $tasksPath" -ForegroundColor Green
    Write-Host "     Matched: $matchCount, Unmatched: $unmatchedCount" -ForegroundColor Gray
    
    # Write log
    $logPath = Join-Path $FeaturePath 'ado-task-mapping.log'
    $logLines = @(
        "Azure DevOps Task Mapping Log"
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ""
        "Configuration:"
        "  Organization: $($config.organization)"
        "  Project: $($config.projectName)"
        "  States: $($config.filterByState -join ', ')"
        "  Iteration: $(if ($config.filterByIteration) { $config.filterByIteration } else { 'all' })"
        ""
        "Summary:"
        "  Total PBIs: $($pbis.Count)"
        "  Matched Tasks: $matchCount"
        "  Unmatched Tasks: $unmatchedCount"
        ""
        "Details:"
        ""
    )
    
    foreach ($match in $matchLog) {
        $logLines += "  $($match.Old) -> $($match.New)"
        $logLines += "    Task: $($match.Description)"
        $logLines += "    PBI: [$($match.PBIState)] $($match.PBITitle)"
        $logLines += ""
    }
    
    Set-Content -Path $logPath -Value $logLines -Encoding UTF8
    Write-Host "[OK] Mapping log written to: $logPath" -ForegroundColor Green
    
    Write-Host "`n=== Hook Complete ===" -ForegroundColor Cyan
    return 0
}

$exitCode = Main
exit $exitCode
