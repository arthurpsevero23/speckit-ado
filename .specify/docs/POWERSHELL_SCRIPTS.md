# PowerShell Scripts Reference

This package ships PowerShell scripts for Azure DevOps setup, workflow automation, and validation.

## Setup and Validation

| Script | Purpose | Example |
|---|---|---|
| `.specify/scripts/setup-ado.ps1` | Interactive Azure DevOps setup and connection test | `./.specify/scripts/setup-ado.ps1` |
| `.specify/scripts/powershell/check-prerequisites.ps1` | Validate current feature/branch context | `./.specify/scripts/powershell/check-prerequisites.ps1 -Json` |
| `.specify/scripts/powershell/test-functionality.ps1` | Validate packaged files and module basics | `./.specify/scripts/powershell/test-functionality.ps1` |
| `.specify/scripts/powershell/deep-test-ado-workflow.ps1` | Deeper workflow validation across create/select/push flows | `./.specify/scripts/powershell/deep-test-ado-workflow.ps1 -DryRunOnly` |
| `.specify/scripts/powershell/validate-consumer-install.ps1` | Validate installation from a consumer project after `npm install` and `npx spec-kit init` | `./.specify/scripts/powershell/validate-consumer-install.ps1` |

## ADO Backlog Operations

| Script | Purpose | Example |
|---|---|---|
| `.specify/scripts/powershell/select-pbi-for-specify.ps1` | Select an existing backlog item and persist context | `./.specify/scripts/powershell/select-pbi-for-specify.ps1 -PbiId 1234` |
| `.specify/scripts/powershell/create-pbi-for-specify.ps1` | Create a backlog item from spec context or overrides | `./.specify/scripts/powershell/create-pbi-for-specify.ps1 -Title "API auth" -DryRun -Json` |
| `.specify/scripts/powershell/push-pbi-refinements.ps1` | Push refined fields from `spec.md` back to ADO | `./.specify/scripts/powershell/push-pbi-refinements.ps1 -DryRun -Json` |
| `.specify/scripts/powershell/create-test-pbis.ps1` | Create sample ADO items for sandbox/testing | `./.specify/scripts/powershell/create-test-pbis.ps1` |

## Feature/Branch Helpers

| Script | Purpose | Example |
|---|---|---|
| `.specify/scripts/powershell/create-feature-from-pbi.ps1` | Create a GitFlow branch from a PBI | `./.specify/scripts/powershell/create-feature-from-pbi.ps1 -PbiId 1234` |
| `.specify/scripts/powershell/create-new-feature.ps1` | Create a feature folder/branch without ADO dependency | `./.specify/scripts/powershell/create-new-feature.ps1 -ShortName my-feature` |
| `.specify/scripts/powershell/setup-plan.ps1` | Initialize plan context for the current feature | `./.specify/scripts/powershell/setup-plan.ps1` |

## Utility Scripts

| Script | Purpose |
|---|---|
| `.specify/scripts/powershell/common.ps1` | Shared path and repository helpers used by other scripts |
| `.specify/scripts/powershell/update-agent-context.ps1` | Update agent-oriented context from project planning artifacts |

## Safety Levels

| Safe to run anytime | Mutates local files | Mutates Azure DevOps |
|---|---|---|
| `test-functionality.ps1` | `setup-ado.ps1` | `create-pbi-for-specify.ps1` |
| `check-prerequisites.ps1` | `select-pbi-for-specify.ps1` | `push-pbi-refinements.ps1` |
| `deep-test-ado-workflow.ps1 -DryRunOnly` | `create-feature-from-pbi.ps1` | `create-test-pbis.ps1` |

## Recommended Validation Sequence

```powershell
npm test
.\.specify\scripts\powershell\test-functionality.ps1
.\.specify\scripts\powershell\deep-test-ado-workflow.ps1 -DryRunOnly
.\.specify\scripts\powershell\validate-consumer-install.ps1
```