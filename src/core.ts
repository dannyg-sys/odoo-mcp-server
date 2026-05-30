// Core Odoo management logic, shared by the MCP server (index.ts) and the CLI
// entry point (cli.ts). Functions here return plain OdooResult objects (text +
// optional isError) — the entry points are responsible for formatting these for
// their respective transports (MCP content envelopes vs. stdout/exit codes).
//
// Structure note: the base directory ($HOME/odoo) is fixed; the Odoo sources
// (odoo/ = CE18, enterprise/ = EE18, odoo19/ = CE19, enterprise19/ = EE19) all
// live inside it. The 18-vs-19 selection is per-project, driven entirely by the
// active odoo.conf (the `; odoo_src` / `; python_venv` markers and addons_path);
// manage_odoo.sh reads those, so no version branching is needed here.
//
// The engine itself is the vendored scripts/manage_odoo.sh; we invoke it by
// absolute path and pass ODOO_BASE so it operates on the resolved base
// regardless of where it (or its ~/.local/bin symlink) lives.

import { execSync } from "child_process";
import { existsSync, readFileSync, readdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import os from "os";

// Absolute path to the vendored engine. This module lives at build/core.js, so
// the repo root is one level up and the script is at <root>/scripts/manage_odoo.sh.
const MANAGE_SCRIPT = join(dirname(dirname(fileURLToPath(import.meta.url))), "scripts", "manage_odoo.sh");

export interface OdooConfig {
  root: string;
  name: string;
}

export interface OdooResult {
  text: string;
  isError?: boolean;
}

// The base directory. Default is $HOME/odoo; we fall back to the legacy
// $HOME/git/odoo18 location during the transition. Both must agree with the
// default baked into scripts/manage_odoo.sh (ODOO_BASE).
const DEFAULT_BASE = join(os.homedir(), "odoo");
const LEGACY_BASE = join(os.homedir(), "git", "odoo18");

// A directory is a usable Odoo base if it has an active odoo.conf or at least
// one project config (odoo-<project>.conf). We no longer require manage_odoo.sh
// to live inside it — the engine is vendored/global now.
function isOdooBase(dir: string): boolean {
  if (!existsSync(dir)) return false;
  if (existsSync(join(dir, "odoo.conf"))) return true;
  try {
    return readdirSync(dir).some((f) => f.startsWith("odoo-") && f.endsWith(".conf"));
  } catch {
    return false;
  }
}

// Resolve the base directory. An explicit override (absolute path, or a name
// resolved under $HOME) always wins; otherwise — and for the legacy "odoo"/
// "odoo18" tokens that older MCP schemas still default to — prefer $HOME/odoo,
// then the legacy $HOME/git/odoo18 location.
export function resolveConfig(baseOverride?: string): OdooConfig {
  const isDefaultToken = !baseOverride || baseOverride === "odoo" || baseOverride === "odoo18";
  if (!isDefaultToken) {
    const root = baseOverride!.startsWith("/") ? baseOverride! : join(os.homedir(), baseOverride!);
    if (!isOdooBase(root)) {
      throw new Error(`Not an Odoo base directory (no odoo.conf / odoo-*.conf): ${root}`);
    }
    return { root, name: root };
  }
  for (const root of [DEFAULT_BASE, LEGACY_BASE]) {
    if (isOdooBase(root)) {
      return { root, name: "Odoo" };
    }
  }
  throw new Error(
    `No Odoo base found. Looked for ${DEFAULT_BASE} and ${LEGACY_BASE} (need an odoo.conf or odoo-*.conf).`
  );
}

// List the available project configurations (odoo-<project>.conf) in a base dir.
export function listProjectNames(config: OdooConfig): string[] {
  try {
    return readdirSync(config.root)
      .filter((f) => f.startsWith("odoo-") && f.endsWith(".conf"))
      .map((f) => f.replace(/^odoo-/, "").replace(/\.conf$/, ""))
      .sort();
  } catch {
    return [];
  }
}

// Build a command that invokes the vendored engine by absolute path.
function manage(args: string): string {
  return `"${MANAGE_SCRIPT}" ${args}`;
}

export function executeCommand(config: OdooConfig, command: string): string {
  try {
    console.error(`[Executing] ${command}`);
    const result = execSync(command, {
      cwd: config.root,
      // Pin the engine's base to the resolved config so the script and core agree.
      env: { ...process.env, ODOO_BASE: config.root },
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer
      timeout: 300000, // 5 minute timeout
    });
    console.error(`[Success] Command completed`);
    return result;
  } catch (error: any) {
    console.error(`[Command Error]`, error.message);
    // execSync throws if exit code is non-zero. Combine stdout and stderr so we
    // still surface warnings and errors from Odoo commands instead of throwing.
    let output = "";
    if (error.stdout) {
      output += error.stdout;
    }
    if (error.stderr) {
      console.error(`[STDERR]`, error.stderr);
      if (output) {
        output += "\n\n=== STDERR ===\n";
      }
      output += error.stderr;
    }

    if (output) {
      return output;
    }

    throw new Error(`Command failed: ${error.message}`);
  }
}

// Smart output filter: collapse verbose Odoo logs to the lines that matter
// (errors always; warnings unless errorOnly), with a status header. See
// OUTPUT_FILTERING.md for the rationale and token-savings figures.
export function filterOdooOutput(output: string, errorOnly: boolean): string {
  const lines = output.split("\n");
  const filtered: string[] = [];

  let hasErrors = false;
  let hasWarnings = false;

  for (const line of lines) {
    const lowerLine = line.toLowerCase();

    // Always include these critical patterns
    if (
      lowerLine.includes("error") ||
      lowerLine.includes("failed") ||
      lowerLine.includes("exception") ||
      lowerLine.includes("traceback") ||
      lowerLine.includes("valueerror") ||
      lowerLine.includes("attributeerror") ||
      lowerLine.includes("importerror") ||
      lowerLine.includes("modulenotfounderror") ||
      lowerLine.includes("syntaxerror") ||
      lowerLine.includes("could not") ||
      lowerLine.includes("cannot") ||
      lowerLine.includes("unable to")
    ) {
      filtered.push(line);
      hasErrors = true;
    }
    // Include warnings only if not in error-only mode
    else if (
      !errorOnly &&
      (lowerLine.includes("warning") ||
        lowerLine.includes("deprecated") ||
        lowerLine.includes("obsolete"))
    ) {
      filtered.push(line);
      hasWarnings = true;
    }
    // Include module update confirmation lines
    else if (
      lowerLine.includes("modules updated") ||
      lowerLine.includes("modules installed") ||
      lowerLine.includes("module loaded") ||
      lowerLine.includes("updating module") ||
      lowerLine.includes("installing module") ||
      lowerLine.includes("server restarted") ||
      lowerLine.includes("odoo started") ||
      lowerLine.includes("frontend updated")
    ) {
      filtered.push(line);
    }
    // Include database-related messages
    else if (
      lowerLine.includes("database") ||
      lowerLine.includes("migrating") ||
      (lowerLine.includes("init") && lowerLine.includes("module"))
    ) {
      filtered.push(line);
    }
  }

  if (filtered.length === 0) {
    return "✓ Operation completed successfully with no errors or warnings.";
  }

  let summary = "";
  if (hasErrors) {
    summary += "⚠️ ERRORS FOUND - Review the details below:\n\n";
  } else if (hasWarnings) {
    summary += "ℹ️ Warnings found (no errors):\n\n";
  }

  return summary + filtered.join("\n");
}

// Parse addons_path entries from the active odoo.conf. Returns absolute paths
// resolved against config.root. Empty array if conf missing or addons_path absent.
export function getAddonsPaths(config: OdooConfig): string[] {
  const confPath = join(config.root, "odoo.conf");
  if (!existsSync(confPath)) return [];
  try {
    const text = readFileSync(confPath, "utf8");
    const match = text.match(/^addons_path\s*=\s*(.+)$/m);
    if (!match) return [];
    return match[1]
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .map((s) => (s.startsWith("/") ? s : join(config.root, s)));
  } catch {
    return [];
  }
}

// --- Operations -----------------------------------------------------------

export function startOdoo(config: OdooConfig): OdooResult {
  const output = executeCommand(config, manage("start"));
  return { text: `Odoo started:\n${output}` };
}

export function stopOdoo(config: OdooConfig): OdooResult {
  const output = executeCommand(config, manage("stop"));
  return { text: `Odoo stopped:\n${output}` };
}

export function restartOdoo(config: OdooConfig): OdooResult {
  const output = executeCommand(config, manage("restart"));
  return { text: `Odoo restarted:\n${output}` };
}

export function checkStatus(config: OdooConfig): OdooResult {
  const output = executeCommand(config, manage("status"));
  return { text: output };
}

export function updateModules(
  config: OdooConfig,
  modules: string,
  errorOnly: boolean
): OdooResult {
  const errorFlag = errorOnly ? " --error-only" : "";
  const output = executeCommand(config, manage(`update ${modules}${errorFlag}`));
  const filteredOutput = filterOdooOutput(output, errorOnly);
  return { text: `Modules updated: ${modules}\n${filteredOutput}` };
}

export function installModules(
  config: OdooConfig,
  modules: string,
  errorOnly: boolean
): OdooResult {
  const errorFlag = errorOnly ? " --error-only" : "";
  const output = executeCommand(config, manage(`install ${modules}${errorFlag}`));
  const filteredOutput = filterOdooOutput(output, errorOnly);
  return { text: `Modules installed: ${modules}\n${filteredOutput}` };
}

export function updateFrontend(
  config: OdooConfig,
  modules: string,
  errorOnly: boolean
): OdooResult {
  const errorFlag = errorOnly ? " --error-only" : "";
  const output = executeCommand(config, manage(`frontend ${modules}${errorFlag}`));
  const filteredOutput = filterOdooOutput(output, errorOnly);
  return { text: `Frontend modules updated: ${modules}\n${filteredOutput}` };
}

export function runTests(
  config: OdooConfig,
  modules?: string,
  testTags?: string,
  errorOnly?: boolean
): OdooResult {
  let args = "test";
  if (modules) args += ` ${modules}`;
  if (testTags) args += ` ${testTags}`;
  if (errorOnly) args += " --error-only";

  const output = executeCommand(config, manage(args));
  return { text: `Test results:\n${output}` };
}

export function startShell(config: OdooConfig): OdooResult {
  return {
    text: `To start an interactive Odoo shell, run this in your terminal:\nODOO_BASE="${config.root}" manage_odoo shell\n\nNote: this is interactive and needs direct terminal access.`,
  };
}

export function getLogs(config: OdooConfig, lines: number): OdooResult {
  const logFile = join(config.root, "odoo.log");
  if (!existsSync(logFile)) {
    return { text: `Log file not found: ${logFile}` };
  }
  const output = executeCommand(config, `tail -n ${lines} odoo.log`);
  return { text: `Last ${lines} lines of odoo.log:\n${output}` };
}

export function listDatabases(config: OdooConfig): OdooResult {
  try {
    const files = readdirSync(config.root);
    const confFiles = files.filter((f) => f.startsWith("odoo") && f.endsWith(".conf"));

    const currentConf = join(config.root, "odoo.conf");
    let currentDb = "unknown";
    if (existsSync(currentConf)) {
      const confContent = readFileSync(currentConf, "utf-8");
      const dbMatch = confContent.match(/db_name\s*=\s*(.+)/);
      if (dbMatch) {
        currentDb = dbMatch[1].trim();
      }
    }

    let output = `Current database: ${currentDb}\n\nAvailable database configurations:\n`;
    confFiles.forEach((file) => {
      const marker = file === "odoo.conf" ? " (active)" : "";
      output += `  - ${file}${marker}\n`;
    });

    return { text: output };
  } catch (error: any) {
    throw new Error(`Failed to list databases: ${error.message}`);
  }
}

export function switchDatabase(config: OdooConfig, project: string): OdooResult {
  // Delegate to manage_odoo.sh switch_config, the single source of truth: it
  // stops Odoo, backs up the current odoo.conf to odoo.conf.prev, activates
  // odoo-<project>.conf, and starts Odoo with the new configuration. On an
  // unknown project it prints the list of available configs (captured here).
  const output = executeCommand(config, manage(`switch_config ${project}`));
  return { text: `Switched to project: ${project}\n${output}` };
}

export function importDatabase(config: OdooConfig, backupFile: string): OdooResult {
  if (!existsSync(backupFile)) {
    throw new Error(`Backup file not found: ${backupFile}`);
  }
  if (!backupFile.endsWith(".zip")) {
    throw new Error("Backup file must be a .zip file");
  }

  try {
    executeCommand(config, `unzip -o "${backupFile}" -d /tmp/odoo_import_temp`);

    const dumpFile = "/tmp/odoo_import_temp/dump.sql";
    if (!existsSync(dumpFile)) {
      throw new Error("Invalid backup: dump.sql not found in backup archive");
    }

    return {
      text: `Database import requires manual steps:\n\n1. Backup extracted to: /tmp/odoo_import_temp\n2. Create/restore PostgreSQL database:\n   dropdb database_name\n   createdb database_name\n   psql database_name < /tmp/odoo_import_temp/dump.sql\n\n3. Restore filestore:\n   cp -r /tmp/odoo_import_temp/filestore/* ~/.local/share/Odoo/filestore/database_name/\n\n4. Update odoo.conf with database name\n5. Restart Odoo\n\nNote: Full automation of this process requires PostgreSQL credentials and is not yet implemented.`,
    };
  } catch (error: any) {
    throw new Error(`Failed to import database: ${error.message}`);
  }
}

export function getProjectDir(config: OdooConfig, project: string): OdooResult {
  const projectPath = join(config.root, project);

  if (!existsSync(projectPath)) {
    return { text: `Project directory not found: ${projectPath}`, isError: true };
  }

  try {
    executeCommand(config, `ls -la ${project} | grep "^l"`);
    const realPath = executeCommand(config, `readlink -f ${project}`).trim();
    return {
      text: `Project directory: ${projectPath}\nReal path: ${realPath}\n\nThis is your custom addons directory for the ${project} project.`,
    };
  } catch (error) {
    return {
      text: `Project directory: ${projectPath}\n\nThis is your custom addons directory for the ${project} project.`,
    };
  }
}

export function getOdooAddonDir(config: OdooConfig): OdooResult {
  // Prefer the addons entry that ends in "/addons" (the Odoo core source's
  // addons dir, e.g. odoo/addons or odoo19/addons). Falls back to odoo/.
  const paths = getAddonsPaths(config);
  const addonPath = paths.find((p) => p.endsWith("/addons")) || join(config.root, "odoo", "addons");
  const odooSrcDir = addonPath.replace(/\/addons$/, "");

  if (!existsSync(addonPath)) {
    return { text: `Odoo core addon directory not found: ${addonPath}`, isError: true };
  }

  return {
    text: `Odoo core source: ${odooSrcDir}\nOdoo core addons directory: ${addonPath}\n\nThis contains the standard Odoo community modules.`,
  };
}

export function getEnterpriseDir(config: OdooConfig): OdooResult {
  // Prefer an addons_path entry whose basename starts with "enterprise"
  // (matches both ./enterprise and ./enterprise19). Falls back to enterprise/.
  const paths = getAddonsPaths(config);
  const enterprisePath =
    paths.find((p) => {
      const basename = p.split("/").pop() || "";
      return basename.startsWith("enterprise");
    }) || join(config.root, "enterprise");

  if (!existsSync(enterprisePath)) {
    return { text: `Enterprise directory not found: ${enterprisePath}`, isError: true };
  }

  return {
    text: `Odoo Enterprise addons directory: ${enterprisePath}\n\nThis contains the Odoo Enterprise modules.`,
  };
}

export function getConfigPath(config: OdooConfig): OdooResult {
  const configPath = join(config.root, "odoo.conf");
  if (!existsSync(configPath)) {
    return { text: `Configuration file not found: ${configPath}`, isError: true };
  }
  return {
    text: `Active Odoo configuration: ${configPath}\n\nThis is the configuration file currently in use by Odoo.`,
  };
}

export function getProjectConfigPath(config: OdooConfig, project: string): OdooResult {
  const configPath = join(config.root, `odoo-${project}.conf`);
  if (!existsSync(configPath)) {
    return {
      text: `Project configuration file not found: ${configPath}\n\nExpected: odoo-${project}.conf`,
      isError: true,
    };
  }
  return {
    text: `Project configuration: ${configPath}\n\nThis is the original configuration for the ${project} project.\nUse 'odoo_switch_database' to make this the active configuration.`,
  };
}
