# Create test PBIs in Azure DevOps for testing spec-kit functionality
# This script creates sample Product Backlog Items to test:
# - Feature creation from PBI
# - Task enrichment/fuzzy matching
# - Complete spec-kit workflow

param(
    [string]$Organization = "arthurpsevero23",
    [string]$Project = "arthur-severo",
    [string]$PatTokenEnvVar = "ADO_PAT_TOKEN"
)

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Azure DevOps Test PBI Creator" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Get PAT token
$patToken = [Environment]::GetEnvironmentVariable($PatTokenEnvVar)
if (-not $patToken) {
    Write-Host "[FAIL] Error: $PatTokenEnvVar environment variable not set" -ForegroundColor Red
    exit 1
}

$authHeader = @{Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$patToken")))" }
$basePath = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems"

# Define test PBIs - using "Product Backlog Item" as standard work type
$testPbis = @(
    @{
        title       = "Implement user authentication with Azure AD"
        description = "Set up Azure AD integration for user login and authorization"
        priority    = 1
    },
    @{
        title       = "Create responsive dashboard layout"
        description = "Design and implement mobile-friendly dashboard using Bootstrap"
        priority    = 2
    },
    @{
        title       = "Fix database connection timeout issue"
        description = "Investigate and resolve connection pool exhaustion"
        priority    = 1
    },
    @{
        title       = "Refactor legacy reporting module"
        description = "Modernize reporting code and add unit tests"
        priority    = 3
    },
    @{
        title       = "Add email notification system"
        description = "Implement async email notifications for user events"
        priority    = 2
    }
)

Write-Host "Creating $($testPbis.Count) test PBIs in: $Organization/$Project" -ForegroundColor Yellow
Write-Host ""

$createdPbis = @()

foreach ($pbi in $testPbis) {
    Write-Host "Creating PBI: '$($pbi.title)'" -ForegroundColor White
    
    $bodyArray = @(
        @{
            op    = "add"
            path  = "/fields/System.Title"
            value = $pbi.title
        },
        @{
            op    = "add"
            path  = "/fields/System.Description"
            value = $pbi.description
        },
        @{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Common.Priority"
            value = $pbi.priority
        },
        @{
            op    = "add"
            path  = "/fields/System.State"
            value = "Active"
        }
    )
    $body = ConvertTo-Json -InputObject $bodyArray -Depth 10

    try {
        # Use "Product Backlog Item" as the work type - API format includes $ prefix
        $workItemType = "%24Product%20Backlog%20Item"  # URL encoded: $Product Backlog Item
        $url = "$basePath/$workItemType`?api-version=7.0"
        
        Write-Host "  URL: $url" -ForegroundColor DarkGray
        
        $response = Invoke-RestMethod `
            -Uri $url `
            -Method POST `
            -Headers $authHeader `
            -ContentType "application/json-patch+json" `
            -Body $body

        Write-Host "  [OK] Created PBI #$($response.id): $($response.fields.'System.Title')" -ForegroundColor Green
        $createdPbis += $response
        
        # Small delay to avoid rate limiting
        Start-Sleep -Milliseconds 500
    }
    catch {
        Write-Host "  [FAIL] Failed to create PBI: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Created $($createdPbis.Count) PBIs:" -ForegroundColor Green
Write-Host ""

foreach ($pbi in $createdPbis) {
    Write-Host "  • PBI #$($pbi.id): $($pbi.fields.'System.Title')" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Run: .\.specify\scripts\powershell\create-feature-from-pbi.ps1" -ForegroundColor Gray
Write-Host "2. Select one of the created PBIs to create a feature branch" -ForegroundColor Gray
Write-Host "3. Test the complete workflow" -ForegroundColor Gray
Write-Host ""
