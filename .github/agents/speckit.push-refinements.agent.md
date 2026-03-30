---
description: Push refined PBI fields from spec.md back to the linked Azure DevOps work item.
handoffs:
  - label: Back to Clarify
    agent: speckit.clarify
    prompt: Continue clarifying the feature specification
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
---

## User Input

```text
$ARGUMENTS
```

You MUST help the user review what will be pushed, then execute the write-back.

## Flow

1. **Check prerequisites**
   - Confirm `.specify/context/selected-pbi.json` exists; read and summarize the linked PBI (ID, title, state).
   - Run `check-prerequisites.ps1 -Json -PathsOnly` to verify an active feature spec exists.

2. **Dry-run preview**
   Run the push script in dry-run mode to extract and display what will change:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\push-pbi-refinements.ps1 -DryRun -Json
   ```
   Parse the JSON output and present the user a **diff summary** table:

   | Field | Will be updated? |
   |---|---|
   | Description | Yes / No |
   | Acceptance Criteria | Yes / No |
   | Tags | Yes / No |
   | Story Points | Yes / No |

   Also display the extracted content for each field that will be updated.

3. **Confirm with user**
   Ask: *"Ready to push these refinements to AB#[ID] in Azure DevOps? (yes/no)"*
   - If the user says no, offer to go **Back to Clarify** to refine further.

4. **Execute push**
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\push-pbi-refinements.ps1 -Json
   ```
   Parse the JSON result and report:
   - Which fields were updated
   - Whether a comment was posted to the work item
   - Direct link to the work item: `https://dev.azure.com/{organization}/{project}/_workitems/edit/{id}`
     (read org and project from `.specify/context/selected-pbi.json`)

5. **On failure**
   - Show the exact error message from the script output.
   - Check if the PAT token is still valid (`ADO_PAT_TOKEN` env var).
   - Suggest retrying or running `/speckit.pickup-task` to re-select the PBI.

## Notes

- Only fields that differ from spec-template.md placeholder values are pushed — empty or default template text is never written to ADO.
- The script wraps markdown content in `<pre>...</pre>` for ADO HTML fields (Description, Acceptance Criteria).
- A comment is automatically posted to the work item after a successful update documenting the branch and fields changed.
