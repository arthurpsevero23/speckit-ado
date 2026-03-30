# spec-kit 🚀

AI-driven specification to task breakdown framework with **Azure DevOps PBI integration** and **GitFlow branching** support.

Transform your specifications into actionable tasks, enriched with Azure DevOps work items and Git-friendly branch names.

## Quick Install

```bash
npm install @arthurpsevero23/spec-kit
```

Or with yarn:
```bash
yarn add @arthurpsevero23/spec-kit
```

## Quick Start

### 1. First Time Setup
```bash
# Copy the setup script to your repo
cp node_modules/@arthurpsevero23/spec-kit/.setup-spec-kit.ps1 .

# Run the setup wizard (PowerShell required)
pwsh -NoProfile -ExecutionPolicy Bypass -File .setup-spec-kit.ps1
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
├── .specify/                    # Spec-kit root (from npm package or git submodule)
│   ├── init-options.json        # Your local configuration
│   ├── modules/
│   │   └── azure-devops-integration.ps1
│   ├── hooks/
│   │   ├── after_tasks.ps1      # Enriches tasks with PBI IDs
│   │   └── ...
│   ├── scripts/
│   │   ├── setup-ado.ps1        # Interactive setup wizard
│   │   └── powershell/
│   │       └── create-feature-from-pbi.ps1
│   └── docs/
│       ├── AZURE_DEVOPS_SETUP.md
│       ├── GITFLOW_SETUP.md
│       └── NPM_ACCOUNT_SETUP.md
├── features/
│   └── feature-branch-name/     # Created by create-feature-from-pbi.ps1
│       ├── spec.md
│       ├── plan.md
│       └── tasks.md             # Generated with [AB#XXXX] task IDs
├── package.json
└── README.md
```

## Documentation

- **[Azure DevOps Setup](./.specify/docs/AZURE_DEVOPS_SETUP.md)** - Complete guide for connecting to Azure DevOps
  - PAT token generation
  - Organization and project configuration
  - WIQL query customization
  - Troubleshooting

- **[GitFlow Workflow](./.specify/docs/GITFLOW_SETUP.md)** - Git branch management with PBI integration
  - Branch naming conventions
  - Creating features from PBIs
  - Release and hotfix procedures
  - CI/CD automation patterns

- **[NPM Account Setup](./.specify/docs/NPM_ACCOUNT_SETUP.md)** - Setting up NPM publishing
  - Creating NPM accounts and scopes
  - Generating authentication tokens
  - Configuring GitHub secrets
  - Publishing new versions

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
- Ensure package.json version matches the git tag (v0.5.0 → "0.5.0")
- Commit and push before creating the tag
- See [NPM Account Setup](./.specify/docs/NPM_ACCOUNT_SETUP.md#troubleshooting)

### "ExecutionPolicy" error in PowerShell
```powershell
# Run PowerShell with bypass policy
pwsh -NoProfile -ExecutionPolicy Bypass -File .\script.ps1
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
- **Git Tags**: Format `v0.5.0` triggers automated NPM publication
- **NPM Package**: Published as `@arthurpsevero23/spec-kit`

Current Version: **0.5.0**

## Publishing Updates

### For Package Maintainers

```bash
# 1. Update version in package.json and any docs
nano package.json  # Change version

# 2. Commit and push
git add .
git commit -m "Bump version to 0.5.1"
git push origin main

# 3. Create and push git tag (triggers GitHub Actions)
git tag v0.5.1
git push origin v0.5.1

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
**Current Version**: 0.5.0  
**Status**: Active Development ✓
