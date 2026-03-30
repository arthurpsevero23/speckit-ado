---
description: Create a backlog PBI in Azure DevOps from the current specification with optional field overrides.
handoffs:
  - label: Run Specify
    agent: speckit.specify
    prompt: Generate or update the specification from this feature context
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
---

## User Input

```text
$ARGUMENTS
```

You MUST guide the user through a safe create workflow: preview first, then create.

## Flow

1. Confirm `.specify/scripts/powershell/create-pbi-for-specify.ps1` exists.
2. Run a dry-run preview command first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\create-pbi-for-specify.ps1 -DryRun -Json`
3. Parse and show preview summary:
   - Title
   - State
   - Iteration/Sprint
   - Priority
   - Story Points
   - Tags
   - Fields that will be applied
4. Ask for explicit confirmation before creation.
5. On confirmation, run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\create-pbi-for-specify.ps1 -Json`
6. Parse and summarize output:
   - PBI ID / Task ID
   - Title
   - URL
   - Context path written (`createdContextPath`)
7. If the user wants immediate `/speckit.specify` continuity against this new item, rerun creation with:
   `-SetAsSelected`

## Failure Handling

If creation fails:
- Show the exact command used.
- Show the error text.
- Check PAT token env var configured in `.specify/init-options.json`.
- Suggest retrying with explicit overrides (`-Title`, `-Sprint`, `-State`, `-Priority`).
