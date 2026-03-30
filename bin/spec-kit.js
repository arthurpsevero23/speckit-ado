#!/usr/bin/env node

import { existsSync, cpSync, readFileSync } from "node:fs";
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
  console.log("  init      Copy .specify template folder to current directory");
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

function copySpecifyTemplate() {
  const sourceSpecify = join(packageRoot, ".specify");
  const sourceSetup = join(packageRoot, ".setup-spec-kit.ps1");
  const targetSpecify = join(process.cwd(), ".specify");
  const targetSetup = join(process.cwd(), ".setup-spec-kit.ps1");

  if (!existsSync(sourceSpecify)) {
    console.error("Template .specify folder not found in package.");
    process.exit(1);
  }

  if (!existsSync(targetSpecify)) {
    cpSync(sourceSpecify, targetSpecify, { recursive: true });
    console.log("Created .specify from package template.");
  } else {
    console.log(".specify already exists. Skipping template copy.");
  }

  if (!existsSync(targetSetup) && existsSync(sourceSetup)) {
    cpSync(sourceSetup, targetSetup);
    console.log("Created .setup-spec-kit.ps1 in current directory.");
  } else if (existsSync(targetSetup)) {
    console.log(".setup-spec-kit.ps1 already exists. Skipping copy.");
  }

  console.log("Initialization complete.");
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
  copySpecifyTemplate();
  process.exit(0);
}

console.error(`Unknown command: ${arg}`);
printHelp();
process.exit(1);
