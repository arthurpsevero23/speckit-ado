---
description: Help the user pick a backlog PBI (by ID or filters) and prepare context for /speckit.specify.
handoffs:
  - label: Run Specify
    agent: speckit.specify
    prompt: Generate a feature specification from the selected PBI context
    send: true
---

## User Input

```text
$ARGUMENTS
```

You MUST help the user pick a single PBI and save context for `/speckit.specify`.

## Flow

1. Confirm `.specify/scripts/powershell/select-pbi-for-specify.ps1` exists.
2. Ask whether to use:
   - direct PBI ID fast path, or
   - interactive filter mode (state, sprint, assigned to, text search)
3. Execute the selector script accordingly:
   - Direct ID example:
     `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\select-pbi-for-specify.ps1 -PbiId 1234`
   - Interactive example:
     `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\select-pbi-for-specify.ps1 -State Active,Committed`
4. Verify `.specify/context/selected-pbi.json` exists and summarize selected fields:
   - ID / Task ID
   - Title
   - State
   - Assigned To
   - Iteration
   - Tags
   - Story Points
5. Instruct user to run `/speckit.specify` with the feature text from the card description.

If selection fails, provide the exact command to retry with a narrower filter.
