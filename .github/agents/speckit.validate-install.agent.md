---
description: Validate that spec-kit was installed correctly in the current repository and that onboarding files are ready.
handoffs:
  - label: Run Specify
    agent: speckit.specify
    prompt: Start or update the feature specification workflow
  - label: Create PBI in ADO
    agent: speckit.create-pbi
    prompt: Create a backlog PBI from this repository context
---

## User Input

```text
$ARGUMENTS
```

You MUST validate the current repository installation before the user starts the workflow.

## Flow

1. Confirm `.specify/scripts/powershell/validate-consumer-install.ps1` exists.
2. Run the validation script first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\.specify\scripts\powershell\validate-consumer-install.ps1`
3. Parse the output and summarize:
   - CLI availability
   - `.specify` initialization status
   - packaged files present
   - smoke test result
   - deep test result / skips
   - ADO schema result / skips
4. If failures exist:
   - show the failing checks clearly
   - recommend the next concrete step (`npx spec-kit init`, `setup-ado.ps1`, or reinstall the package)
5. If all checks pass:
   - tell the user the repository is ready
   - suggest the next likely step: `/speckit.specify`, `/speckit.pickup-task`, or `/speckit.create-pbi`

## Notes

- This validation is intended for consumer repositories after installing the npm package or local tarball.
- The script supports both installed-package projects and running from the source repository.
- `SKIP` results are valid when optional ADO or deep workflow checks were not requested.
