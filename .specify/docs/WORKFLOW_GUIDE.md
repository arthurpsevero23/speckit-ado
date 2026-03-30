# Workflow Guide

This guide explains how the packaged agents and scripts fit together in day-to-day usage.

## Entry Points

Use one of these starting points depending on what you already have:

| Entry point | Use when |
|---|---|
| `npx spec-kit init` | You are installing the package in a repository for the first time |
| `/speckit.specify` | You want to create a new feature specification from requirements |
| `/speckit.pickup-task` | You already have an Azure DevOps backlog item and want to pull it into the workflow |
| `/speckit.create-pbi` | You have a spec draft and want to create a backlog item in Azure DevOps |

## Recommended Authoring Flow

1. Initialize the repository with `npx spec-kit init`.
2. Configure Azure DevOps with `./.specify/scripts/setup-ado.ps1`.
3. Start spec authoring with `/speckit.specify`.
4. Run `/speckit.clarify` to reduce ambiguity.
5. Run `/speckit.plan` to create the implementation plan.
6. Run `/speckit.tasks` to generate actionable tasks.
7. Use `/speckit.push-refinements` if the refined specification should update the linked ADO item.

## ADO-Centric Flows

### Pick up an existing item

1. Run `/speckit.pickup-task`.
2. The agent calls `select-pbi-for-specify.ps1`.
3. Context is written to `.specify/context/selected-pbi.json`.
4. Run `/speckit.specify` to generate the spec with linked work item metadata.

### Create a new item from the spec

1. Start from `/speckit.specify` or an existing spec draft.
2. Run `/speckit.create-pbi`.
3. The agent dry-runs and then calls `create-pbi-for-specify.ps1`.
4. Context is written to `.specify/context/created-pbi.json`.

### Push refinements back to ADO

1. Update the linked work item section in the generated `spec.md`.
2. Run `/speckit.push-refinements`.
3. The agent dry-runs and then calls `push-pbi-refinements.ps1`.
4. Description, acceptance criteria, tags, and estimate are pushed back when present.

## Handoffs

The agents expose handoff buttons to reduce command memorization.

Typical handoffs:

- `speckit.specify` -> `speckit.pickup-task`
- `speckit.specify` -> `speckit.create-pbi`
- `speckit.clarify` -> `speckit.push-refinements`
- `speckit.clarify` -> `speckit.plan`
- `speckit.pickup-task` -> `speckit.specify`

## Context Files

Two local context files are used to connect ADO steps across commands:

| File | Written by | Purpose |
|---|---|---|
| `.specify/context/selected-pbi.json` | `select-pbi-for-specify.ps1` | Stores the currently selected backlog item for `/speckit.specify` |
| `.specify/context/created-pbi.json` | `create-pbi-for-specify.ps1` | Stores the newly created backlog item metadata |

These files are local workflow state and should not be committed to source control.

## Validation Commands

Use these when onboarding or debugging:

```powershell
# Package smoke test
npm test

# Script/file validation
.\.specify\scripts\powershell\test-functionality.ps1

# End-to-end ADO workflow validation
.\.specify\scripts\powershell\deep-test-ado-workflow.ps1 -DryRunOnly
```