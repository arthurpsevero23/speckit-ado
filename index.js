/**
 * @arthurpsevero23/spec-kit
 * 
 * AI-driven specification to task breakdown framework with Azure DevOps PBI integration.
 * 
 * This package provides:
 * - PowerShell modules for Azure DevOps integration
 * - GitFlow-aware branching scripts
 * - Task enrichment hooks for spec-kit workflow
 * - Interactive configuration wizards
 * 
 * Installation:
 *   npm install @arthurpsevero23/spec-kit
 * 
 * Setup:
 *   Copy .specify/ folder to your project root
 *   Configure .specify/init-options.json with your Azure DevOps details
 *   Run .specify/scripts/setup-ado.ps1 for interactive setup
 * 
 * Documentation:
 *   - AZURE_DEVOPS_SETUP.md - Azure DevOps integration guide
 *   - GITFLOW_SETUP.md - GitFlow workflow documentation
 *   - README.md - Project overview
 */

import { readFileSync } from 'node:fs';

const _pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));

export const VERSION = _pkg.version;

export const PACKAGE_INFO = {
  name: _pkg.name,
  version: VERSION,
  description:
    "AI-driven specification to task breakdown framework with Azure DevOps PBI integration",
  author: "Arthur Severo",
  license: "MIT"
};

export const INSTALLATION_NOTES = {
  folder: ".specify",
  configFile: ".specify/init-options.json",
  setupScript: ".specify/scripts/setup-ado.ps1",
  documentation: {
    azureDevOps: "AZURE_DEVOPS_SETUP.md",
    gitflow: "GITFLOW_SETUP.md"
  }
};

/**
 * Get package information
 * @returns {Object} Package metadata
 */
export function getPackageInfo() {
  return PACKAGE_INFO;
}

/**
 * Get installation instructions
 * @returns {string} Formatted installation notes
 */
export function getInstallationInstructions() {
  return `
@arthurpsevero23/spec-kit v${VERSION}

Quick Start:
1. npm install @arthurpsevero23/spec-kit
2. Copy .specify/ folder to your project root
3. Run .specify/scripts/setup-ado.ps1 (PowerShell)
4. Create first feature with create-feature-from-pbi.ps1

For detailed setup, see: AZURE_DEVOPS_SETUP.md
For workflow docs, see: GITFLOW_SETUP.md
  `;
}

export default {
  VERSION,
  PACKAGE_INFO,
  INSTALLATION_NOTES,
  getPackageInfo,
  getInstallationInstructions
};
