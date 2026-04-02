---
description: Create a backlog PBI in Azure DevOps from the current specification with optional field overrides.
handoffs:
  - label: Validate Install
    agent: speckit.validate-install
    prompt: Validate this repository installation and onboarding setup
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
2. Run a dry-run preview first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\create-pbi-for-specify.ps1 -DryRun -Json`
3. Parse the `mode` field and show the preview summary:
   - **`flat`**: Title, Work Item Type, State, Iteration/Sprint, Priority, Story Points, Tags, Fields applied
   - **`hierarchy`**: Epic title + type + state, then each child story (number, title, type, state); sprint/tags shared across all items
4. Ask for explicit confirmation before creation.
5. On confirmation, run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\create-pbi-for-specify.ps1 -Json`
6. Parse the `mode` field and summarize output:
   - **`flat`**: PBI ID / Task ID, Title, URL, `createdContextPath`
   - **`hierarchy`**: Epic ID + URL (`epicId`, `epicUrl`), then each child's ID + URL from `children[]`, `createdContextPath`
7. If the user wants immediate `/speckit.specify` continuity, rerun with `-SetAsSelected`.
   In hierarchy mode, `-SetAsSelected` automatically selects the first child issue.
8. To force hierarchy mode regardless of `createHierarchy` in config:
   `create-pbi-for-specify.ps1 -CreateHierarchy -Json`

## Hierarchy Mode

Hierarchy mode activates when either:
- `ado.creation.hierarchy.createHierarchy` is `true` in `.specify/init-options.json`, OR
- The `-CreateHierarchy` flag is passed directly.

When active, the script parses `### User Story N — Title` headings from the active spec and creates:
1. One **Epic** (configurable via `epicWorkItemType`) for the overall feature
2. One **Issue** (configurable via `storyWorkItemType`) per user story, each linked as a child of the Epic

Configure types and states in `init-options.json` under `ado.creation.hierarchy`:
- `createHierarchy` — set to `true` to enable by default
- `epicWorkItemType` — e.g. `"Epic"`
- `epicState` — initial state for the Epic (e.g. `"To Do"`)
- `storyWorkItemType` — e.g. `"Issue"`

## Failure Handling

If creation fails:
- Show the exact command used.
- Show the error text.
- Check PAT token env var configured in `.specify/init-options.json`.
- Suggest retrying with explicit overrides (`-Title`, `-Sprint`, `-State`, `-Priority`).
