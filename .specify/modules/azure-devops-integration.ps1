<#
.SYNOPSIS
Azure DevOps integration module for spec-kit.
Provides functions to fetch PBIs from Azure DevOps and map them to task IDs.

.DESCRIPTION
This module handles all interactions with the Azure DevOps REST API, including:
- Fetching Product Backlog Items (PBIs) with filtering
- Mapping PBI data to task ID format
- Matching task descriptions to PBIs using fuzzy matching

.NOTES
Requires a PAT token set in environment variable or configuration.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Configuration Loading
# ============================================================================

<#
.SYNOPSIS
Load Azure DevOps configuration from init-options.json

.PARAMETER InitOptionsPath
Path to the init-options.json file

.OUTPUTS
PSCustomObject with ADO configuration
#>
function Get-AzureDevOpsConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InitOptionsPath
    )

    if (-not (Test-Path $InitOptionsPath)) {
        throw "init-options.json not found at: $InitOptionsPath"
    }

    $config = Get-Content $InitOptionsPath -Raw | ConvertFrom-Json
    
    if (-not $config.ado) {
        throw "Azure DevOps configuration not found in init-options.json. Add 'ado' section."
    }

    if (-not $config.ado.enabled) {
        throw "Azure DevOps integration is not enabled. Set ado.enabled to true in init-options.json"
    }

    if (-not $config.ado.organization) {
        throw "Azure DevOps organization not configured (ado.organization)"
    }

    if (-not $config.ado.projectName) {
        throw "Azure DevOps project name not configured (ado.projectName)"
    }

    return $config.ado
}

<#
.SYNOPSIS
Get PAT token from environment variable or configuration

.PARAMETER Config
Azure DevOps configuration object

.OUTPUTS
String containing the PAT token

.EXAMPLE
$token = Get-PATToken $config
#>
function Get-PATToken {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $envVarName = $Config.patTokenEnvVar
    $token = [Environment]::GetEnvironmentVariable($envVarName)

    if (-not $token) {
        throw "PAT token not found in environment variable '$envVarName'. Set the environment variable or use 'setup-ado.ps1' to configure."
    }

    return $token
}

# ============================================================================
# Azure DevOps REST API Interactions
# ============================================================================

<#
.SYNOPSIS
Fetch PBIs from Azure DevOps with filtering

.PARAMETER Organization
Azure DevOps organization name

.PARAMETER ProjectName
Azure DevOps project name

.PARAMETER PatToken
Personal Access Token for authentication

.PARAMETER FilterByState
Array of states to include (e.g., "Active", "Committed", "New")

.PARAMETER FilterByIteration
Iteration path filter (glob pattern)

.OUTPUTS
Array of PSCustomObject with PBI ID and Title
#>
function Get-AzureDevOpsPBIs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,
        
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        
        [Parameter(Mandatory = $true)]
        [string]$PatToken,
        
        [Parameter(Mandatory = $false)]
        [string[]]$FilterByState = @("Active", "Committed"),
        
        [Parameter(Mandatory = $false)]
        [string]$FilterByIteration = "",

        [Parameter(Mandatory = $false)]
        [string]$FilterByAssignedTo = "",

        [Parameter(Mandatory = $false)]
        [string]$SearchText = "",

        [Parameter(Mandatory = $false)]
        [int]$Top = 200
    )

    $headers = New-AdoHeaders -PatToken $PatToken
    $stateFilter = Build-StateFilterExpression -States $FilterByState

    $query = "SELECT TOP $Top [System.Id] " +
             "FROM WorkItems " +
             "WHERE [System.WorkItemType] = 'Product Backlog Item'"

    if ($stateFilter) {
        $query += " AND ($stateFilter)"
    }

    if ($FilterByIteration) {
        $safeIteration = $FilterByIteration -replace "'", "''"
        $query += " AND [System.IterationPath] UNDER '$safeIteration'"
    }

    if ($FilterByAssignedTo) {
        $safeAssigned = $FilterByAssignedTo -replace "'", "''"
        $query += " AND [System.AssignedTo] CONTAINS '$safeAssigned'"
    }

    if ($SearchText) {
        $safeSearch = $SearchText -replace "'", "''"
        $query += " AND [System.Title] CONTAINS '$safeSearch'"
    }

    $query += " ORDER BY [System.ChangedDate] DESC"

    Write-Verbose "Azure DevOps WIQL Query: $query"

    $wiqlResponse = Invoke-AdoWiqlQuery -Organization $Organization -ProjectName $ProjectName -Headers $headers -Query $query
    $ids = @($wiqlResponse.workItems | ForEach-Object { [int]$_.id })

    if ($ids.Count -eq 0) {
        return @()
    }

    $workItems = Get-AdoWorkItemsByIds -Organization $Organization -ProjectName $ProjectName -Headers $headers -Ids $ids
    return Convert-AdoWorkItemsToPBIObjects -WorkItems $workItems
}

<#
.SYNOPSIS
Fetch a single PBI with rich fields by ID.

.PARAMETER Organization
Azure DevOps organization name.

.PARAMETER ProjectName
Azure DevOps project name.

.PARAMETER PatToken
Personal Access Token for authentication.

.PARAMETER PbiId
Work item ID.

.OUTPUTS
PSCustomObject with rich PBI fields.
#>
function Get-AzureDevOpsPBIDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$PatToken,

        [Parameter(Mandatory = $true)]
        [int]$PbiId
    )

    $headers = New-AdoHeaders -PatToken $PatToken
    $workItems = @(Get-AdoWorkItemsByIds -Organization $Organization -ProjectName $ProjectName -Headers $headers -Ids @($PbiId))

    if ($workItems.Count -eq 0) {
        return $null
    }

    $mapped = Convert-AdoWorkItemsToPBIObjects -WorkItems $workItems
    return $mapped[0]
}

function New-AdoHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PatToken
    )

    return @{
        Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PatToken")))"
        "Content-Type" = "application/json"
    }
}

function Build-StateFilterExpression {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$States
    )

    if (-not $States -or $States.Count -eq 0) {
        return ""
    }

    $parts = @()
    foreach ($state in $States) {
        $safeState = $state -replace "'", "''"
        $parts += "[System.State] = '$safeState'"
    }

    return ($parts -join " OR ")
}

function Invoke-AdoWiqlQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $adoUrl = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/wiql?api-version=7.0"
    $body = @{ query = $Query } | ConvertTo-Json

    try {
        return Invoke-RestMethod -Uri $adoUrl -Method Post -Headers $Headers -Body $body
    }
    catch {
        throw "Failed to execute WIQL query: $($_.Exception.Message)"
    }
}

function Get-AdoWorkItemsByIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [int[]]$Ids
    )

    if (-not $Ids -or $Ids.Count -eq 0) {
        return @()
    }

    $allItems = @()
    $fields = @(
        'System.Id',
        'System.Title',
        'System.State',
        'System.IterationPath',
        'System.AssignedTo',
        'System.Tags',
        'System.Description',
        'Microsoft.VSTS.Common.AcceptanceCriteria',
        'Microsoft.VSTS.Scheduling.StoryPoints',
        'Microsoft.VSTS.Scheduling.Effort'
    ) -join ','

    $chunkSize = 200
    for ($i = 0; $i -lt $Ids.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize - 1, $Ids.Count - 1)
        $chunk = $Ids[$i..$end]
        $idCsv = ($chunk -join ',')

        $url = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems?ids=$idCsv&fields=$fields&api-version=7.0"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $Headers
            if ($response.value) {
                $allItems += @($response.value)
            }
        }
        catch {
            throw "Failed to fetch work item details: $($_.Exception.Message)"
        }
    }

    return @($allItems)
}

function Get-AdoAssignedToName {
    param(
        [Parameter(Mandatory = $false)]
        $AssignedToField
    )

    if (-not $AssignedToField) {
        return ''
    }

    if ($AssignedToField -is [string]) {
        return $AssignedToField
    }

    if ($AssignedToField.PSObject -and $AssignedToField.PSObject.Properties['displayName']) {
        return [string]$AssignedToField.displayName
    }

    return [string]$AssignedToField
}

function Convert-AdoWorkItemsToPBIObjects {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkItems
    )

    $mapped = @()

    foreach ($workItem in $WorkItems) {
        $fields = $workItem.fields
        $storyPoints = $null

        $hasStoryPoints = $fields.PSObject.Properties.Match('Microsoft.VSTS.Scheduling.StoryPoints').Count -gt 0
        $hasEffort = $fields.PSObject.Properties.Match('Microsoft.VSTS.Scheduling.Effort').Count -gt 0
        $hasAssignedTo = $fields.PSObject.Properties.Match('System.AssignedTo').Count -gt 0
        $hasDescription = $fields.PSObject.Properties.Match('System.Description').Count -gt 0
        $hasAcceptanceCriteria = $fields.PSObject.Properties.Match('Microsoft.VSTS.Common.AcceptanceCriteria').Count -gt 0
        $hasTags = $fields.PSObject.Properties.Match('System.Tags').Count -gt 0

        if ($hasStoryPoints -and $fields.'Microsoft.VSTS.Scheduling.StoryPoints' -ne $null) {
            $storyPoints = $fields.'Microsoft.VSTS.Scheduling.StoryPoints'
        }
        elseif ($hasEffort -and $fields.'Microsoft.VSTS.Scheduling.Effort' -ne $null) {
            $storyPoints = $fields.'Microsoft.VSTS.Scheduling.Effort'
        }

        $mapped += [PSCustomObject]@{
            Id                 = [int]$workItem.id
            Title              = [string]$fields.'System.Title'
            State              = [string]$fields.'System.State'
            Iteration          = [string]$fields.'System.IterationPath'
            AssignedTo         = Get-AdoAssignedToName -AssignedToField $(if ($hasAssignedTo) { $fields.'System.AssignedTo' } else { $null })
            Description        = if ($hasDescription -and $fields.'System.Description') { [string]$fields.'System.Description' } else { '' }
            AcceptanceCriteria = if ($hasAcceptanceCriteria -and $fields.'Microsoft.VSTS.Common.AcceptanceCriteria') { [string]$fields.'Microsoft.VSTS.Common.AcceptanceCriteria' } else { '' }
            Tags               = if ($hasTags -and $fields.'System.Tags') { [string]$fields.'System.Tags' } else { '' }
            StoryPoints        = $storyPoints
        }
    }

    return $mapped
}

# ============================================================================
# PBI Write-Back
# ============================================================================

<#
.SYNOPSIS
Update fields of an Azure DevOps work item using JSON Patch.

.PARAMETER Organization
Azure DevOps organization name.

.PARAMETER ProjectName
Azure DevOps project name.

.PARAMETER PatToken
Personal Access Token for authentication.

.PARAMETER PbiId
Work item ID to update.

.PARAMETER Description
New description text (markdown wrapped in <pre>). Optional.

.PARAMETER AcceptanceCriteria
New acceptance criteria text (markdown wrapped in <pre>). Optional.

.PARAMETER Tags
Semicolon-separated tag string. Optional.

.PARAMETER StoryPoints
Numeric story points / effort estimate. Optional.

.OUTPUTS
PSCustomObject with the updated work item response.
#>
function Update-AzureDevOpsPBI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$PatToken,

        [Parameter(Mandatory = $true)]
        [int]$PbiId,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$AcceptanceCriteria = "",

        [Parameter(Mandatory = $false)]
        [string]$Tags = "",

        [Parameter(Mandatory = $false)]
        $StoryPoints = $null
    )

    $patchOps = [System.Collections.Generic.List[hashtable]]::new()

    if ($Description) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.Description"
            value = $Description
        })
    }

    if ($AcceptanceCriteria) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
            value = $AcceptanceCriteria
        })
    }

    if ($Tags) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.Tags"
            value = $Tags
        })
    }

    if ($null -ne $StoryPoints) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Scheduling.StoryPoints"
            value = $StoryPoints
        })
    }

    if ($patchOps.Count -eq 0) {
        throw "No fields supplied to Update-AzureDevOpsPBI. At least one field must be provided."
    }

    $patchHeaders = New-AdoHeaders -PatToken $PatToken
    $patchHeaders["Content-Type"] = "application/json-patch+json"

    $body = $patchOps | ConvertTo-Json -Depth 5

    # ConvertTo-Json wraps a single item as an object, not array — force array
    if ($patchOps.Count -eq 1) {
        $body = "[$body]"
    }

    $url = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems/$($PbiId)?api-version=7.0"

    try {
        return Invoke-RestMethod -Uri $url -Method Patch -Headers $patchHeaders -Body $body
    }
    catch {
        throw "Failed to update work item $PbiId`: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Post a discussion comment to an Azure DevOps work item.

.PARAMETER Organization
Azure DevOps organization name.

.PARAMETER ProjectName
Azure DevOps project name.

.PARAMETER PatToken
Personal Access Token for authentication.

.PARAMETER PbiId
Work item ID.

.PARAMETER CommentText
HTML or plain text comment body.

.OUTPUTS
PSCustomObject with the created comment response.
#>
function Add-AzureDevOpsPBIComment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$PatToken,

        [Parameter(Mandatory = $true)]
        [int]$PbiId,

        [Parameter(Mandatory = $true)]
        [string]$CommentText
    )

    $headers = New-AdoHeaders -PatToken $PatToken
    $body = @{ text = $CommentText } | ConvertTo-Json

    $url = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems/$($PbiId)/comments?api-version=7.0-preview.3"

    try {
        return Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
    }
    catch {
        throw "Failed to post comment to work item $PbiId`: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Create a new Product Backlog Item in Azure DevOps.

.PARAMETER Organization
Azure DevOps organization name.

.PARAMETER ProjectName
Azure DevOps project name.

.PARAMETER PatToken
Personal Access Token for authentication.

.PARAMETER Title
Work item title.

.PARAMETER Description
Work item description (HTML/markdown text).

.PARAMETER AcceptanceCriteria
Work item acceptance criteria (HTML/markdown text).

.PARAMETER Tags
Semicolon-separated tag string.

.PARAMETER StoryPoints
Numeric estimate.

.PARAMETER Priority
Priority value.

.PARAMETER State
Initial work item state.

.PARAMETER Iteration
Iteration path.

.PARAMETER WorkItemType
Azure DevOps work item type name (e.g., "Issue", "Product Backlog Item").

.OUTPUTS
PSCustomObject with the created work item response.
#>
function New-AzureDevOpsPBI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$PatToken,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [string]$AcceptanceCriteria = "",

        [Parameter(Mandatory = $false)]
        [string]$Tags = "",

        [Parameter(Mandatory = $false)]
        $StoryPoints = $null,

        [Parameter(Mandatory = $false)]
        $Priority = $null,

        [Parameter(Mandatory = $false)]
        [string]$State = "",

        [Parameter(Mandatory = $false)]
        [string]$Iteration = "",

        [Parameter(Mandatory = $false)]
        [string]$WorkItemType = "Product Backlog Item"
    )

    if (-not $Title.Trim()) {
        throw "Title is required to create a Product Backlog Item."
    }

    $patchOps = [System.Collections.Generic.List[hashtable]]::new()
    $patchOps.Add(@{
        op    = "add"
        path  = "/fields/System.Title"
        value = $Title.Trim()
    })

    if ($Description) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.Description"
            value = $Description
        })
    }

    if ($AcceptanceCriteria) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
            value = $AcceptanceCriteria
        })
    }

    if ($Tags) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.Tags"
            value = $Tags
        })
    }

    if ($null -ne $StoryPoints) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Scheduling.StoryPoints"
            value = $StoryPoints
        })
    }

    if ($null -ne $Priority) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/Microsoft.VSTS.Common.Priority"
            value = $Priority
        })
    }

    if ($State) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.State"
            value = $State
        })
    }

    if ($Iteration) {
        $patchOps.Add(@{
            op    = "add"
            path  = "/fields/System.IterationPath"
            value = $Iteration
        })
    }

    $headers = New-AdoHeaders -PatToken $PatToken
    $headers["Content-Type"] = "application/json-patch+json"

    $body = $patchOps | ConvertTo-Json -Depth 6
    $encodedType = [System.Uri]::EscapeDataString($WorkItemType)
    $workItemTypePath = "`$$encodedType"
    $url = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems/${workItemTypePath}?api-version=7.0"

    try {
        return Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($State -and $_.Exception.Response -and ([int]$_.Exception.Response.StatusCode -eq 400)) {
            throw "Failed to create work item (HTTP 400). The State '$State' may be invalid for this project's process template. Common valid values: 'To Do' (Basic), 'New' (Scrum), 'Active' (CMMI). Update ado.creation.defaultState in init-options.json. Original error: $errMsg"
        }
        throw "Failed to create Product Backlog Item: $errMsg"
    }
}

function Set-WorkItemParent {
<#
.SYNOPSIS
Set the parent of an Azure DevOps work item by adding a Hierarchy-Reverse relation.

.PARAMETER Organization
Azure DevOps organization name.

.PARAMETER ProjectName
Azure DevOps project name.

.PARAMETER PatToken
Personal Access Token for authentication.

.PARAMETER ChildId
Work item ID of the child.

.PARAMETER ParentId
Work item ID of the parent (epic).
#>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$PatToken,

        [Parameter(Mandatory = $true)]
        [int]$ChildId,

        [Parameter(Mandatory = $true)]
        [int]$ParentId
    )

    $headers = New-AdoHeaders -PatToken $PatToken
    $headers['Content-Type'] = 'application/json-patch+json'

    $parentUrl = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems/$ParentId"
    $patchOps  = @(
        @{
            op    = 'add'
            path  = '/relations/-'
            value = @{
                rel        = 'System.LinkTypes.Hierarchy-Reverse'
                url        = $parentUrl
                attributes = @{ comment = '' }
            }
        }
    )

    $body = $patchOps | ConvertTo-Json -Depth 6
    if ($patchOps.Count -eq 1) { $body = "[$body]" }

    $url = "https://dev.azure.com/$Organization/$ProjectName/_apis/wit/workitems/${ChildId}?api-version=7.0"

    try {
        return Invoke-RestMethod -Uri $url -Method Patch -Headers $headers -Body $body
    }
    catch {
        throw "Failed to set parent $ParentId for child work item ${ChildId}: $($_.Exception.Message)"
    }
}

# ============================================================================
# PBI to Task Mapping
# ============================================================================

<#
.SYNOPSIS
Convert PBI ID to task ID format (e.g., AB#1234)

.PARAMETER PBIId
The PBI work item ID

.OUTPUTS
String in format "AB#XXXX"

.EXAMPLE
$taskId = ConvertTo-TaskId -PBIId 1234
# Returns: AB#1234
#>
function ConvertTo-TaskId {
    param(
        [Parameter(Mandatory = $true)]
        [int]$PBIId
    )
    
    return "AB#$($PBIId)"
}

<#
.SYNOPSIS
Calculate Levenshtein distance between two strings for fuzzy matching

.PARAMETER String1
First string

.PARAMETER String2
Second string

.OUTPUTS
Integer representing the edit distance

.NOTES
Lower distance = higher similarity. Used for matching task descriptions to PBI titles.
#>
function Get-LevenshteinDistance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$String1,
        
        [Parameter(Mandatory = $true)]
        [string]$String2
    )

    $s1 = $String1.ToLower()
    $s2 = $String2.ToLower()
    
    $len1 = $s1.Length
    $len2 = $s2.Length
    
    if ($len1 -eq 0) { return $len2 }
    if ($len2 -eq 0) { return $len1 }
    
    # Create character arrays
    [char[]]$chars1 = $s1
    [char[]]$chars2 = $s2
    
    # Initialize distance matrix
    $prevRow = @(0..($len2))
    
    for ($i = 1; $i -le $len1; $i++) {
        $currRow = @($i)
        
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($chars1[$i - 1] -eq $chars2[$j - 1]) { 0 } else { 1 }
            
            $del = $prevRow[$j] + 1
            $ins = $currRow[$j - 1] + 1
            $sub = $prevRow[$j - 1] + $cost
            
            $currRow += ([Math]::Min([Math]::Min($del, $ins), $sub))
        }
        
        $prevRow = $currRow
    }
    
    return $prevRow[-1]
}

<#
.SYNOPSIS
Match a task description to a PBI by fuzzy string similarity

.PARAMETER TaskDescription
The task description text to match

.PARAMETER PBIs
Array of PBI objects with Id and Title properties

.PARAMETER SimilarityThreshold
Threshold for considering a match (0-100, percentage)

.OUTPUTS
PSCustomObject with matched PBI or $null if no match found

.EXAMPLE
$pbi = Find-MatchingPBI -TaskDescription "Create user authentication" -PBIs $pbis -SimilarityThreshold 80
#>
function Find-MatchingPBI {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskDescription,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$PBIs,
        
        [Parameter(Mandatory = $false)]
        [int]$SimilarityThreshold = 75
    )

    # Remove common prefixes from task description
    $cleanDescription = $TaskDescription -replace '^\[.*?\]\s*', '' -replace '^-\s*', ''
    
    $bestMatch = $null
    $bestScore = 0
    
    foreach ($pbi in $PBIs) {
        $distance = Get-LevenshteinDistance -String1 $cleanDescription -String2 $pbi.Title
        $maxLength = [Math]::Max($cleanDescription.Length, $pbi.Title.Length)
        $similarity = (1 - ($distance / $maxLength)) * 100
        
        if ($similarity -gt $bestScore) {
            $bestScore = $similarity
            $bestMatch = $pbi
        }
    }
    
    if ($bestScore -ge $SimilarityThreshold) {
        Write-Verbose "Matched task '$cleanDescription' to PBI '$($bestMatch.Title)' (similarity: $bestScore%)"
        return $bestMatch
    }
    
    Write-Verbose "No match found for task '$cleanDescription' (best score: $bestScore%)"
    return $null
}

<#
.SYNOPSIS
Match multiple task descriptions to PBIs with interactive disambiguation

.PARAMETER TaskDescriptions
Array of task description strings

.PARAMETER PBIs
Array of PBI objects

.OUTPUTS
Hashtable mapping task descriptions to PBI objects

.NOTES
Optionally prompts user for disambiguation if multiple matches are close in score.
#>
function Find-AllMatchingPBIs {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TaskDescriptions,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$PBIs
    )

    $mapping = @{}
    
    foreach ($description in $TaskDescriptions) {
        $match = Find-MatchingPBI -TaskDescription $description -PBIs $PBIs
        if ($match) {
            $mapping[$description] = $match
        }
    }
    
    return $mapping
}

# ============================================================================
# Functions are now available for use via dot-sourcing
# ============================================================================
