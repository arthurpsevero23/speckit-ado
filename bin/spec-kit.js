#!/usr/bin/env node

import { existsSync, cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageRoot = dirname(__dirname);

function printHelp() {
  console.log("spec-kit CLI");
  console.log("");
  console.log("Usage:");
  console.log("  spec-kit init");
  console.log("  spec-kit --help");
  console.log("  spec-kit --version");
  console.log("");
  console.log("Commands:");
  console.log("  init      Initialize spec-kit in current directory (copies .specify, agents, and prompts)");
}

function printVersion() {
  try {
    const pkgPath = join(packageRoot, "package.json");
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
    console.log(pkg.version || "0.0.0");
  } catch {
    console.log("0.0.0");
  }
}

/**
 * Copy a directory from the package, always overwriting (framework-owned files).
 */
function copyFrameworkDir(name, source, target) {
  if (!existsSync(source)) {
    console.log(`  ⚠ Source ${name} not found in package. Skipping.`);
    return;
  }
  mkdirSync(target, { recursive: true });
  cpSync(source, target, { recursive: true, force: true });
  console.log(`  ✔ ${name} copied (overwrites framework-owned files).`);
}

function initProject() {
  const cwd = process.cwd();

  // --- .specify ---
  const sourceSpecify = join(packageRoot, ".specify");
  const targetSpecify = join(cwd, ".specify");

  if (!existsSync(sourceSpecify)) {
    console.error("Template .specify folder not found in package.");
    process.exit(1);
  }

  if (!existsSync(targetSpecify)) {
    cpSync(sourceSpecify, targetSpecify, { recursive: true });
    console.log("  ✔ .specify created from package template.");
  } else {
    // Overwrite framework-owned subdirs, skip user config
    const frameworkDirs = ["docs", "hooks", "modules", "scripts", "templates"];
    for (const dir of frameworkDirs) {
      const src = join(sourceSpecify, dir);
      const dest = join(targetSpecify, dir);
      if (existsSync(src)) {
        cpSync(src, dest, { recursive: true, force: true });
      }
    }
    // Overwrite framework-owned root files
    for (const file of ["extensions.yml"]) {
      const src = join(sourceSpecify, file);
      const dest = join(targetSpecify, file);
      if (existsSync(src)) {
        cpSync(src, dest, { force: true });
      }
    }
    // Skip init-options.json if it already exists (user config)
    const initOptsSource = join(sourceSpecify, "init-options.json");
    const initOptsTarget = join(targetSpecify, "init-options.json");
    if (!existsSync(initOptsTarget) && existsSync(initOptsSource)) {
      const initOpts = JSON.parse(readFileSync(initOptsSource, "utf8"));
      const pkg = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));
      initOpts.speckit_version = pkg.version;
      writeFileSync(initOptsTarget, JSON.stringify(initOpts, null, 2) + "\n", "utf8");
      console.log("  ✔ init-options.json created (default config).");
    } else {
      console.log("  ⏭ init-options.json already exists. Skipping (user config).");
    }
    console.log("  ✔ .specify framework files updated.");
  }

  // --- .setup-spec-kit.ps1 ---
  const sourceSetup = join(packageRoot, ".setup-spec-kit.ps1");
  const targetSetup = join(cwd, ".setup-spec-kit.ps1");
  if (existsSync(sourceSetup)) {
    cpSync(sourceSetup, targetSetup, { force: true });
    console.log("  ✔ .setup-spec-kit.ps1 copied.");
  }

  // --- .vscode/settings.json ---
  const sourceVsSettings = join(packageRoot, ".vscode", "settings.json");
  const targetVsDir = join(cwd, ".vscode");
  const targetVsSettings = join(targetVsDir, "settings.json");
  if (existsSync(sourceVsSettings)) {
    if (!existsSync(targetVsSettings)) {
      mkdirSync(targetVsDir, { recursive: true });
      cpSync(sourceVsSettings, targetVsSettings);
      console.log("  ✔ .vscode/settings.json created (default VS Code settings).");
    } else {
      console.log("  ⏭ .vscode/settings.json already exists. Skipping.");
    }
  }

  // --- .github/agents ---
  const sourceAgents = join(packageRoot, ".github", "agents");
  const targetAgents = join(cwd, ".github", "agents");
  copyFrameworkDir(".github/agents", sourceAgents, targetAgents);

  // --- .github/prompts ---
  const sourcePrompts = join(packageRoot, ".github", "prompts");
  const targetPrompts = join(cwd, ".github", "prompts");
  copyFrameworkDir(".github/prompts", sourcePrompts, targetPrompts);

  console.log("");
  console.log("Initialization complete.");
  console.log("Next steps:");
  console.log("  1. Commit the new .specify/, .github/agents/, and .github/prompts/ folders");
  console.log("  2. Run: powershell -ExecutionPolicy Bypass -File .\\node_modules\\@arthurpsevero23\\spec-kit\\.setup-spec-kit.ps1");
  console.log("  3. Use /speckit.specify in VS Code Copilot Chat");
}

const arg = process.argv[2];

if (!arg || arg === "--help" || arg === "-h") {
  printHelp();
  process.exit(0);
}

if (arg === "--version" || arg === "-v") {
  printVersion();
  process.exit(0);
}

if (arg === "init") {
  initProject();
  process.exit(0);
}

console.error(`Unknown command: ${arg}`);
printHelp();
process.exit(1);
