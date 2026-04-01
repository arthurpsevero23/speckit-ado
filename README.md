# spec-kit 🚀

AI-driven specification to task breakdown framework with **Azure DevOps PBI integration** and **GitFlow branching** support.

Transform your specifications into actionable tasks, enriched with Azure DevOps work items and Git-friendly branch names.

## Quick Install

```bash
npm install @arthurpsevero23/spec-kit
```

Then run the setup wizard:

```powershell
powershell -ExecutionPolicy Bypass -File .\node_modules\@arthurpsevero23\spec-kit\.setup-spec-kit.ps1
```

## Quick Start

### 1. First Time Setup
```bash
# Install the package
npm install @arthurpsevero23/spec-kit

# Run the setup wizard (installs, initializes, and copies agents/prompts)
powershell -ExecutionPolicy Bypass -File .\node_modules\@arthurpsevero23\spec-kit\.setup-spec-kit.ps1
```

### 2. Configure Azure DevOps
```powershell
# Run the interactive ADO setup
.\.specify\scripts\setup-ado.ps1

# You'll need:
# - Azure DevOps Organization URL
# - Project Name
# - Personal Access Token (PAT)
```

### 3. Create Your First Feature from a PBI
```powershell
# Fetch PBIs and create a GitFlow branch
.\.specify\scripts\powershell\create-feature-from-pbi.ps1

# Select a PBI and it will:
# - Create a proper GitFlow branch (e.g., feature/AB#1234-feature-name)
# - Set up the feature directory structure
# - Initialize feature specification
```

### 4. Generate Specification and Tasks
```bash
# Start the spec-kit workflow
# In VS Code: use Copilot Chat with `/speckit.specify`
# (CLI currently provides initialization command only: `npx spec-kit init`)

# The workflow will:
# ✓ Generate specification from requirements
# ✓ Create detailed implementation plan
# ✓ Generate actionable tasks
# ✓ Enrich tasks with Azure DevOps PBI IDs
# ✓ Output tasks in your tasks.md with [AB#1234] format
```

## Workflow Architecture

The package has two entry surfaces:

- CLI for repository initialization: `spec-kit init`
- Copilot agents for the authoring workflow inside VS Code

Recommended flow:

1. `npm install @arthurpsevero23/spec-kit`
2. `powershell -ExecutionPolicy Bypass -File .\node_modules\@arthurpsevero23\spec-kit\.setup-spec-kit.ps1`
3. Run `./.specify/scripts/setup-ado.ps1`
4. Start with `/speckit.specify`
5. Optionally use `/speckit.pickup-task` to attach an existing ADO item first
6. Continue with `/speckit.clarify`, `/speckit.plan`, and `/speckit.tasks`
7. Use `/speckit.push-refinements` to sync refined fields back to Azure DevOps

## Agents Reference

### Core Workflow Agents

#### `/speckit.specify` — Create or Update Feature Specification
The starting point for most workflows. Takes a natural language feature description and generates a structured specification document (`spec.md`) using the spec template. If `.specify/context/selected-pbi.json` exists (written by `/speckit.pickup-task`), it merges PBI metadata (ID, title, description, acceptance criteria, state, iteration, tags, story points) into the spec as traceability context. Supports extension hooks via `.specify/extensions.yml` (`before_specify`). Hands off to `/speckit.clarify`, `/speckit.plan`, `/speckit.create-pbi`, `/speckit.pickup-task`, or `/speckit.validate-install`.

#### `/speckit.clarify` — Resolve Ambiguous Requirements
Runs after `/speckit.specify` and before `/speckit.plan`. Performs a structured ambiguity and coverage scan across 9 categories (functional scope, domain/data model, interaction/UX, non-functional attributes, integrations, edge cases, constraints, terminology, completion signals). Marks each category as Clear / Partial / Missing, then asks up to 5 highly targeted clarification questions. Encodes answers directly back into the spec file. Hands off to `/speckit.plan` or `/speckit.push-refinements`.

#### `/speckit.plan` — Generate Implementation Plan
Takes the completed spec and generates design artifacts following the plan template. Fills technical context, runs a constitution check against `.specify/memory/constitution.md`, then produces Phase 0 (research.md for unknowns) and Phase 1 artifacts (data-model.md, contracts/, quickstart.md). Updates agent context via `update-agent-context.ps1`. Supports `before_plan` and `after_plan` extension hooks. Hands off to `/speckit.tasks` or `/speckit.checklist`.

#### `/speckit.tasks` — Generate Implementation Tasks
Reads plan.md, spec.md, and optional design artifacts (data-model.md, contracts/, research.md, quickstart.md) to generate a dependency-ordered `tasks.md`. Organizes tasks by user story priority: Phase 1 (setup), Phase 2 (foundational prerequisites), Phase 3+ (one phase per user story in priority order). Generates a dependency graph and parallel execution examples. Supports `before_tasks` and `after_tasks` extension hooks — the `after_tasks` hook enriches task IDs from `[T001]` to `[AB#1234]` format via ADO integration. Hands off to `/speckit.analyze` or `/speckit.implement`.

#### `/speckit.implement` — Execute Implementation Plan
Processes all tasks defined in `tasks.md` and executes them. Before starting, checks any checklists in the feature's `checklists/` directory — if any checklist items are incomplete, it stops and asks for confirmation before proceeding. Supports `before_implement` extension hooks. Reads the full task list and works through each task sequentially.

### Azure DevOps Integration Agents

#### `/speckit.pickup-task` — Select a Backlog PBI
Fetches PBIs from Azure DevOps and lets you select one to use as context for `/speckit.specify`. Supports two modes: direct PBI ID fast path (`-PbiId 1234`) or interactive filter mode (by state, sprint, assigned to, text search). Writes the selected PBI to `.specify/context/selected-pbi.json` with all fields (ID, title, state, assigned to, iteration, tags, story points). Hands off to `/speckit.specify` or `/speckit.validate-install`.

#### `/speckit.create-pbi` — Create a New ADO Work Item
Creates a new PBI in Azure DevOps from the current specification. Uses a safe two-step workflow: first runs a dry-run preview showing title, state, iteration, priority, story points, and tags, then asks for explicit confirmation before creating. After creation, reports the PBI ID, title, and URL. Supports `-SetAsSelected` to immediately set the new PBI as context for `/speckit.specify`. Hands off to `/speckit.specify`, `/speckit.plan`, or `/speckit.validate-install`.

#### `/speckit.push-refinements` — Sync Refined Fields Back to ADO
Pushes refined specification fields back to the linked Azure DevOps work item. Runs a dry-run preview first showing which fields (description, acceptance criteria, tags, story points) will be updated, then asks for confirmation. After push, reports updated fields, whether a comment was posted to the work item, and a direct link. Only pushes fields that differ from template placeholder values — empty or default text is never written. Hands off to `/speckit.clarify` or `/speckit.plan`.

### Quality & Validation Agents

#### `/speckit.analyze` — Cross-Artifact Consistency Analysis
Read-only analysis agent that runs after `/speckit.tasks`. Scans `spec.md`, `plan.md`, and `tasks.md` for inconsistencies, duplications, ambiguities, and underspecified items. Builds semantic models (requirements inventory, user story inventory, task coverage mapping, constitution rule set) and runs detection passes for duplication, coverage gaps, and constitution violations. Constitution conflicts are automatically CRITICAL severity. Outputs a structured report with up to 50 findings and an optional remediation plan (requires explicit approval before any edits).

#### `/speckit.checklist` — Generate Domain-Specific Checklists
Generates custom checklists that act as "unit tests for requirements writing" — they validate quality, clarity, and completeness of requirements, not implementation correctness. Asks up to 3 contextual clarifying questions (scope, risk, depth, audience, boundaries) derived from the feature domain, then generates checklist items like "Are visual hierarchy requirements defined for all card types?" or "Is 'prominent display' quantified with specific sizing?". Reads spec.md, plan.md, and tasks.md for context.

#### `/speckit.validate-install` — Verify Repository Setup
Runs `validate-consumer-install.ps1` to check that spec-kit was installed correctly in the consumer repository. Validates CLI availability, `.specify` initialization status, packaged file presence, smoke test results, deep test results, and ADO schema. If failures exist, recommends the next concrete step (`npx spec-kit init`, `setup-ado.ps1`, or reinstall). If all checks pass, suggests starting with `/speckit.specify`, `/speckit.pickup-task`, or `/speckit.create-pbi`. Hands off to `/speckit.specify` or `/speckit.create-pbi`.

### Governance & Utility Agents

#### `/speckit.constitution` — Manage Project Constitution
Creates or updates the project constitution at `.specify/memory/constitution.md` from a template. Collects principle values interactively or from user input, fills all placeholder tokens, and increments the version using semantic versioning (MAJOR for principle removals/redefinitions, MINOR for additions, PATCH for clarifications). Propagates changes across dependent templates (plan-template.md, spec-template.md, tasks-template.md) and produces a sync impact report. Hands off to `/speckit.specify`.

#### `/speckit.taskstoissues` — Convert Tasks to GitHub Issues
Reads the generated `tasks.md` and creates GitHub Issues for each task using the GitHub MCP server. Extracts the Git remote URL and verifies it's a GitHub repository before proceeding. Will not create issues in repositories that don't match the remote URL. Requires the `github/github-mcp-server/issue_write` tool.

## Features

### 🔷 Azure DevOps Integration
- Automatically fetch PBIs from your Azure DevOps board
- Match generated tasks to PBI titles using fuzzy matching (Levenshtein distance)
- Transform task IDs from `[T001]` to `[AB#1234]` format
- Filter by PBI state (Active, Committed, etc.)
- Filter by iteration/sprint

### 🌿 GitFlow Branching
- Automatic branch creation in GitFlow format: `feature/<pbi-id>-<description>`
- Support for feature, bugfix, refactor, and change request work types
- Interactive PBI selection UI
- Direct links to open PBIs in Azure DevOps

### 📋 Spec-Kit Workflow
Built on the powerful spec-kit framework:
- **Specify** → Transform requirements into detailed specifications
- **Plan** → Create implementation strategies with time estimates
- **Tasks** → Generate verifiable, independent tasks
- **Hooks** → Post-process with Azure DevOps enrichment

### ⚙️ Configuration
- Single `init-options.json` per repository
- Shared across local team installations
- Environment variable support for secrets (PAT tokens)
- Hierarchical configuration (spec-kit base + ADO extensions)

## Architecture

```
your-repo/
├── .github/
│   ├── agents/                  # Copilot agents (copied by spec-kit init, framework-owned)
│   │   ├── speckit.analyze.agent.md
│   │   ├── speckit.checklist.agent.md
│   │   ├── speckit.clarify.agent.md
│   │   ├── speckit.constitution.agent.md
│   │   ├── speckit.create-pbi.agent.md
│   │   ├── speckit.implement.agent.md
│   │   ├── speckit.pickup-task.agent.md
│   │   ├── speckit.plan.agent.md
│   │   ├── speckit.push-refinements.agent.md
│   │   ├── speckit.specify.agent.md
│   │   ├── speckit.tasks.agent.md
│   │   ├── speckit.taskstoissues.agent.md
│   │   └── speckit.validate-install.agent.md
│   └── prompts/                 # Copilot prompts (copied by spec-kit init, framework-owned)
│       ├── speckit.analyze.prompt.md
│       ├── speckit.checklist.prompt.md
│       ├── speckit.clarify.prompt.md
│       ├── speckit.constitution.prompt.md
│       ├── speckit.create-pbi.prompt.md
│       ├── speckit.implement.prompt.md
│       ├── speckit.pickup-task.prompt.md
│       ├── speckit.plan.prompt.md
│       ├── speckit.push-refinements.prompt.md
│       ├── speckit.specify.prompt.md
│       ├── speckit.tasks.prompt.md
│       ├── speckit.taskstoissues.prompt.md
│       └── speckit.validate-install.prompt.md
├── .specify/                    # Spec-kit root (copied by spec-kit init)
│   ├── init-options.json        # Your local configuration (user-owned, not overwritten)
│   ├── extensions.yml
│   ├── modules/
│   │   └── azure-devops-integration.ps1
│   ├── hooks/
│   │   ├── after_tasks.ps1      # Enriches tasks with PBI IDs
│   │   └── after_tasks-test.ps1
│   ├── scripts/
│   │   ├── setup-ado.ps1        # Interactive setup wizard
│   │   └── powershell/
│   │       ├── check-prerequisites.ps1
│   │       ├── common.ps1
│   │       ├── create-feature-from-pbi.ps1
│   │       ├── create-new-feature.ps1
│   │       ├── create-pbi-for-specify.ps1
│   │       ├── create-test-pbis.ps1
│   │       ├── deep-test-ado-workflow.ps1
│   │       ├── push-pbi-refinements.ps1
│   │       ├── select-pbi-for-specify.ps1
│   │       ├── setup-plan.ps1
│   │       ├── test-functionality.ps1
│   │       ├── update-agent-context.ps1
│   │       └── validate-consumer-install.ps1
│   ├── templates/
│   │   ├── agent-file-template.md
│   │   ├── checklist-template.md
│   │   ├── constitution-template.md
│   │   ├── plan-template.md
│   │   ├── spec-template.md
│   │   └── tasks-template.md
│   └── docs/
│       ├── AZURE_DEVOPS_SETUP.md
│       ├── GITFLOW_SETUP.md
│       ├── POWERSHELL_SCRIPTS.md
│       └── WORKFLOW_GUIDE.md
├── specs/
│   └── 001-feature-name/        # Created by create-new-feature/create-feature-from-pbi.ps1
│       ├── spec.md
│       ├── plan.md
│       └── tasks.md             # Generated with [AB#XXXX] task IDs
├── package.json
└── README.md
```

> **Note:** `.github/agents/` and `.github/prompts/` are copied into your repo by `spec-kit init` and should be committed.
> They are **overwritten** on every `init` run (framework-owned). Do not edit them — customizations will be lost on update.

## Documentation

- **[Azure DevOps Setup](./.specify/docs/AZURE_DEVOPS_SETUP.md)** - Complete guide for connecting to Azure DevOps
  - PAT token generation
  - Organization and project configuration
  - WIQL query customization
  - Troubleshooting

- **[Workflow Guide](./.specify/docs/WORKFLOW_GUIDE.md)** - Agent entry points, handoffs, and recommended execution path
  - Which agent to start with
  - How ADO context flows between steps
  - When to create, pick up, or push backlog items

- **[PowerShell Scripts Reference](./.specify/docs/POWERSHELL_SCRIPTS.md)** - Parameters and examples for packaged scripts
  - Setup and validation scripts
  - ADO create/select/push commands
  - Deep test command for end-to-end validation

- **[GitFlow Workflow](./.specify/docs/GITFLOW_SETUP.md)** - Git branch management with PBI integration
  - Branch naming conventions
  - Creating features from PBIs
  - Release and hotfix procedures
  - CI/CD automation patterns

## Environment Setup

### Prerequisites
- **PowerShell** 5.1+ (included with Windows 10+)
- **Node.js** 14+  (for npm commands)
- **Git** 2.0+ (for version control)
- **Azure DevOps** account with at least one project

### Windows Setup
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Install Node.js
# Download from: https://nodejs.org/

# Verify installation
npm --version
git --version
```

### macOS/Linux Setup
```bash
# Install with Homebrew
brew install node

# Verify installation
npm --version
git --version
```

## Troubleshooting

### "ADO_PAT_TOKEN not found in environment"
```bash
# Set the environment variable
# Windows PowerShell:
$env:ADO_PAT_TOKEN = "your-pat-token-here"

# macOS/Linux bash:
export ADO_PAT_TOKEN="your-pat-token-here"

# Or add to your .bashrc / $PROFILE for persistence
```

### "No PBIs found"
- Ensure your Azure DevOps board has PBIs in the filtered states
- Check if filter criteria (state, iteration) are too restrictive
- Verify organization and project names in init-options.json

### "Version mismatch" error during NPM publish
- Ensure package.json version matches the git tag (e.g. `v1.2.3` → `"1.2.3"`)
- Commit and push before creating the tag

### "ExecutionPolicy" error in PowerShell
```powershell
# Run PowerShell with bypass policy
pwsh -NoProfile -ExecutionPolicy Bypass -File .\script.ps1
```

### Validate Your Installation
```powershell
# Package-level smoke test
npm test

# Core script validation
.\.specify\scripts\powershell\test-functionality.ps1

# Deeper ADO workflow validation
.\.specify\scripts\powershell\deep-test-ado-workflow.ps1 -DryRunOnly

# Consumer-project installation validation
.\.specify\scripts\powershell\validate-consumer-install.ps1
```

## Configuration Examples

### Minimal Setup
```json
{
  "ado": {
    "enabled": true,
    "organization": "your-org",
    "projectName": "your-project",
    "patTokenEnvVar": "ADO_PAT_TOKEN"
  }
}
```

### Advanced Setup with Filters
```json
{
  "ado": {
    "enabled": true,
    "organization": "your-org",
    "projectName": "your-project",
    "patTokenEnvVar": "ADO_PAT_TOKEN",
    "filterByState": ["Active", "Committed"],
    "filterByIteration": "Sprint 42",
    "excludeWorkTypes": ["Epic", "Bug"]
  }
}
```

## Versioning

- **spec-kit**: Follows semantic versioning (MAJOR.MINOR.PATCH)
- **Git Tags**: Format `vX.Y.Z` triggers automated NPM publication
- **NPM Package**: Published as `@arthurpsevero23/spec-kit`

Current Version: **0.6.0**

## Publishing Updates

### For Package Maintainers

```bash
# 1. Update version in package.json and any docs
nano package.json  # Change version

# 2. Commit and push
git add .
git commit -m "Bump version to X.Y.Z"
git push origin main

# 3. Create and push git tag (triggers GitHub Actions)
git tag vX.Y.Z
git push origin vX.Y.Z

# 4. Watch the publish workflow
# GitHub → Actions → "Publish to NPM"
# Should complete in 1-2 minutes

# 5. Verify on npmjs.com
# https://www.npmjs.com/package/@arthurpsevero23/spec-kit
```

## API Reference

### PowerShell Functions

#### Get-AzureDevOpsPBIs
Fetch work items from Azure DevOps with filtering.

```powershell
. .\azure-devops-integration.ps1
$pbis = Get-AzureDevOpsPBIs -State "Active" -Iteration "Sprint 42"
```

#### Find-MatchingPBI
Find the best matching PBI for a task description.

```powershell
$pbi = Find-MatchingPBI -TaskDescription "Implement user authentication" -ThresholdPercentage 70
```

#### ConvertTo-TaskId
Convert PBI ID to formatted task ID.

```powershell
$taskId = ConvertTo-TaskId -PbiId 1234  # Returns "AB#1234"
```

## Contributing

Contributions welcome! Please ensure:
- PowerShell scripts follow consistent style
- Documentation is updated for new features
- Version bumped according to semver
- Git tag created for NPM publication

## License

MIT - See LICENSE file for details

## Support & Resources

- **GitHub Issues**: Report bugs or request features
- **Azure DevOps Docs**: https://docs.microsoft.com/en-us/azure/devops/
- **spec-kit Framework**: Built on the spec-kit AI framework
- **NPM Docs**: https://docs.npmjs.com/

## Roadmap

- [ ] Web-based configuration UI
- [ ] Support for GitHub Issues in addition to ADO
- [ ] Automatic branch cleanup after feature completion
- [ ] Integration with VS Code sidebar (#18)
- [ ] Additional language templates (Java, Go, Rust)
- [ ] Custom field mapping for Azure DevOps

## Related Projects

- **spec-kit** - Parent framework for spec-based development
- **create-feature-from-pbi.ps1** - Interactive GitFlow + ADO integration
- **setup-ado.ps1** - Configuration wizard

## Author

**Arthur Severo** - [@arthurpsevero23](https://github.com/arthurpsevero23)

---

**Last Updated**: March 2026  
**Current Version**: 0.6.0  
**Status**: Active Development ✓
