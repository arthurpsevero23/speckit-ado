/**
 * @arthurpsevero23/spec-kit
 *
 * Azure DevOps extension for the spec-kit AI framework.
 * This package is a CLI tool — use `npx spec-kit init` to set up your project.
 */

import { readFileSync } from 'node:fs';

const _pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'));

export const VERSION = _pkg.version;
export const PACKAGE_NAME = _pkg.name;

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
