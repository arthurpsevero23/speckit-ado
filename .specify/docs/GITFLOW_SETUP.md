# GitFlow Branch Naming with Azure DevOps PBI Integration

This guide explains how to create features using GitFlow naming conventions integrated with Azure DevOps PBIs.

## Overview

Instead of sequential numbering (001-feature-name), features now follow GitFlow:

```
feature/1234-short-description
bugfix/5678-fix-bug-title
refactor/9012-improve-code
cr_42/3456-code-review-changes
```

Where:
- **feature** | **bugfix** | **refactor** = work type
- **1234** = Azure DevOps PBI ID
- **short-description** = auto-generated from PBI title

## Setup

### Prerequisites

1. ✓ Azure DevOps integration enabled (`.specify/init-options.json`)
2. ✓ PAT token set in environment variable: `ADO_PAT_TOKEN`
3. ✓ Git repository initialized with **develop** and **main** branches

### New Script

The script is located at:
```
.specify/scripts/powershell/create-feature-from-pbi.ps1
```

## How to Use

### Method 1: Interactive Selection (Recommended)

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1
```

This will:
1. Fetch all active PBIs from Azure DevOps
2. Display them with numbers
3. Prompt you to select one
4. Create the branch automatically

**Output:**
```
[1] AB#1234 - Add user authentication [Active]
[2] AB#5678 - Fix login timeout [Active]
[3] AB#9012 - Refactor database queries [Active]

Enter number (1-3): 1

Selected PBI:
  ID: AB#1234
  Title: Add user authentication
  State: Active

Creating branch: feature/1234-add-user-authentication
[OK] Branch created successfully

=== Feature Created ===
Branch: feature/1234-add-user-authentication
PBI: AB#1234
...
```

### Method 2: Specify PBI ID Directly

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 1234
```

### Method 3: With Custom Description

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 1234 -Description "auth-system-setup"
```

Creates: `feature/1234-auth-system-setup`

### Method 4: For Bug Fixes

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 5678 -WorkType bugfix
```

Creates: `bugfix/5678-short-description`

### Method 5: For Refactoring

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 9012 -WorkType refactor
```

Creates: `refactor/9012-short-description`

### Method 6: Open PBI Automatically

```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 1234 -Browse
```

Opens the PBI in Azure DevOps after creating the branch.

## GitFlow Branches Overview

### Feature Branches (from develop)

```
feature/<pbi-id>-<description>
```

Example:
```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 1234
# Creates: feature/1234-add-authentication
```

### Bug Fix Branches (from develop)

```
bugfix/<pbi-id>-<description>
```

Example:
```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 5678 -WorkType bugfix
# Creates: bugfix/5678-fix-login-error
```

### Refactoring Branches (from develop)

```
refactor/<pbi-id>-<description>
```

Example:
```powershell
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1 -PbiId 9012 -WorkType refactor
# Creates: refactor/9012-optimize-queries
```

### Release Branches (Manual)

Create manually when releasing:
```bash
git checkout -b release/v1.0.0 develop
```

### Hotfix Branches (Manual)

Create manually for urgent production fixes:
```bash
git checkout -b hotfix/v1.0.1-critical-fix main
```

## Workflow Example

### 1. Create a feature from PBI

```powershell
# Interactively select PBI
. .\.specify\scripts\powershell\create-feature-from-pbi.ps1

# Output:
# Branch: feature/1234-add-authentication
# PBI: AB#1234
```

### 2. Edit the specification

```powershell
code specs/feature/1234-add-authentication/spec.md
```

### 3. Run spec-kit workflow

```powershell
/specify  # Create spec with AI
/plan     # Generate architecture plan
/tasks    # Generate task list (enriched with PBI ID)
```

### 4. Tasks use PBI ID

The tasks.md will show:
```markdown
- [ ] [AB#1234] Implement OAuth2 provider
- [ ] [AB#1234] Add user model to database
- [ ] [AB#1234] Create authentication API endpoints
```

### 5. Commit and push

```bash
git add .
git commit -m "spec: initialize authentication feature (AB#1234)"
git push origin feature/1234-add-authentication
```

### 6. Create Pull Request

Create PR from `feature/1234-add-authentication` → `develop`

When merged, the branch automatically links work items in Azure DevOps.

## Long-lived Branches

### main / master
- Production-ready code
- Only receives code from release/ and hotfix/ branches
- Tags mark releases: v1.0.0, v1.0.1, etc.

### develop
- Integration branch for features
- Source for feature/, bugfix/, refactor/ branches
- Destination for merged PRs
- Pre-release testing happens here

## Key Differences from Old Numbering

| Aspect | Old (001-feature) | New (GitFlow) |
|--------|-------------------|---------------|
| Branch name | `001-user-auth` | `feature/1234-user-auth` |
| PBI tracking | Manual mapping | Automatic via PBI ID |
| Work type clarity | Hidden in description | Explicit in prefix |
| Release handling | No convention | Dedicated release/ branches |
| Hotfixes | No convention | Dedicated hotfix/ branches |

## Troubleshooting

### Error: "No PBIs found matching filter criteria"

**Solutions:**
1. Create PBIs in your Azure DevOps board first
2. Make sure they're in the "Active" or "Committed" state
3. Check filter in `.specify/init-options.json`:
   ```json
   "filterByState": ["Active", "Committed", "New"]
   ```

### Error: "Failed to create branch"

**Solutions:**
1. Make sure you have a git repository initialized
2. Ensure `develop` branch exists:
   ```bash
   git branch develop
   git push origin develop
   ```
3. Check git credentials are configured

### Error: "PAT token not found"

**Solution:**
Set the environment variable:
```powershell
$env:ADO_PAT_TOKEN = "your-token-here"
# Or permanently:
[Environment]::SetEnvironmentVariable("ADO_PAT_TOKEN", "your-token", "User")
```

## Advanced Configuration

### Change Filter States

Edit `.specify/init-options.json`:

```json
{
  "ado": {
    "filterByState": ["Active", "Committed", "New", "In Progress"]
  }
}
```

### Filter by Sprint

Edit `.specify/init-options.json`:

```json
{
  "ado": {
    "filterByIteration": "arthur-severo\\Sprint 26"
  }
}
```

## Integration with CI/CD

The branch naming convention enables automation:

```yaml
# Example GitHub Actions
name: Feature Branch Workflow

on:
  push:
    branches:
      - 'feature/**'
      - 'bugfix/**'
      - 'refactor/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Extract PBI ID
        run: |
          BRANCH=${{ github.head_ref }}
          PBI_ID=$(echo $BRANCH | sed -E 's/[a-z_]+\/([0-9]+)-.*/\1/')
          echo "PBI_ID=$PBI_ID" >> $GITHUB_ENV
      - name: Run tests
        run: npm test
      - name: Update PBI
        run: |
          # Link test results to PBI
          echo "Tests passed for PBI AB#${{ env.PBI_ID }}"
```

## Related Documentation

- [Azure DevOps Setup](./AZURE_DEVOPS_SETUP.md)
- [Spec-Kit Workflow](./)
- [GitFlow Reference](https://nvie.com/posts/a-successful-git-branching-model/)
