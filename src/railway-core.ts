// Core Railway-Odoo management logic, shared by railway-cli.ts. Manages an
// Odoo instance deployed on Railway (e.g. ~/git/faceline) — module
// update/install runs inside the ALREADY-RUNNING container via `railway ssh`
// (no rebuild), followed by `railway restart` (fast, no rebuild) to bring in
// the freshly-migrated registry. `railway up` (a full rebuild) is reserved
// for actual code changes via deploy().
//
// Reuses filterOdooOutput() from core.ts so update/install output gets the
// exact same "✓ clean" / "⚠️ ERRORS FOUND" / "ℹ️ Warnings found" treatment as
// the local odoo-manage skill.

import { execFileSync, execSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { filterOdooOutput } from "./core.js";

export interface RailwayConfig {
  dir: string;
  service: string;
  environment: string;
  confPath: string;
  dbVars: {
    host: string;
    port: string;
    user: string;
    password: string;
    database: string;
  };
}

export interface OdooResult {
  text: string;
  isError?: boolean;
}

const DEFAULT_DB_VARS = {
  host: "DB_HOST",
  port: "DB_PORT",
  user: "DB_USER",
  password: "DB_PASSWORD",
  database: "PGDATABASE",
};

// Resolve config for the target project. Directory is the project identity
// (matches how `railway` itself resolves the linked project/service from
// cwd) — an optional <dir>/.railway-odoo.json overrides service/environment/
// confPath/dbVars for projects that diverge from faceline's conventions.
export function resolveRailwayConfig(dir: string): RailwayConfig {
  const defaults: RailwayConfig = {
    dir,
    service: "odoo",
    environment: "production",
    confPath: "/etc/odoo/odoo.conf",
    dbVars: DEFAULT_DB_VARS,
  };
  const configPath = join(dir, ".railway-odoo.json");
  if (!existsSync(configPath)) return defaults;
  try {
    const overrides = JSON.parse(readFileSync(configPath, "utf8"));
    return {
      dir,
      service: overrides.service || defaults.service,
      environment: overrides.environment || defaults.environment,
      confPath: overrides.confPath || defaults.confPath,
      dbVars: { ...defaults.dbVars, ...(overrides.dbVars || {}) },
    };
  } catch (error: any) {
    throw new Error(`Failed to parse ${configPath}: ${error.message}`);
  }
}

function railway(args: string[], config: RailwayConfig, timeoutMs = 300000): string {
  try {
    console.error(`[Executing] railway ${args.join(" ")}`);
    const result = execFileSync("railway", args, {
      cwd: config.dir,
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024,
      timeout: timeoutMs,
    });
    console.error(`[Success] Command completed`);
    return result;
  } catch (error: any) {
    console.error(`[Command Error]`, error.message);
    let output = "";
    if (error.stdout) output += error.stdout;
    if (error.stderr) {
      console.error(`[STDERR]`, error.stderr);
      if (output) output += "\n\n=== STDERR ===\n";
      output += error.stderr;
    }
    if (output) return output;
    throw new Error(`railway ${args.join(" ")} failed: ${error.message}`);
  }
}

// Fetch the service's Railway variables (JSON), not trusted to already be
// present in a `railway ssh` shell's own env — this documented CLI path
// works regardless of whether that assumption holds.
function fetchDbVars(config: RailwayConfig): Record<string, string> {
  const output = railway(
    ["variable", "list", "-s", config.service, "-e", config.environment, "--json"],
    config
  );
  const vars = JSON.parse(output);
  const resolved: Record<string, string> = {};
  for (const [key, varName] of Object.entries(config.dbVars)) {
    if (!(varName in vars)) {
      throw new Error(`Railway variable '${varName}' (needed for ${key}) not found on service '${config.service}'`);
    }
    resolved[key] = vars[varName];
  }
  return resolved;
}

const HTTP_UP_PATTERN = (msg: string) => {
  const lower = msg.toLowerCase();
  return lower.includes("http service") && lower.includes("running on");
};

const BUILD_FAILURE_PATTERN = (msg: string) => {
  const lower = msg.toLowerCase();
  return lower.includes("build failed") || lower.includes("deployment failed") || lower.includes("crashed");
};

// Poll `railway logs --json` (non-streaming, fetches a fresh window each
// call) until a line matches the HTTP-up pattern or a failure pattern shows,
// or timeoutMs elapses. `sinceIso`, when given, ignores any log line timestamped
// before it — otherwise a stale HTTP-up line from an *earlier* restart (still
// within the last-50-lines window) can be mistaken for confirmation of the
// restart this call just triggered, reporting success before the real one
// even happens.
async function waitForServerUp(config: RailwayConfig, timeoutMs: number, sinceIso?: string): Promise<OdooResult> {
  const pollIntervalMs = 3000;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const output = railway(
      ["logs", "-s", config.service, "-e", config.environment, "-n", "50", "--json"],
      config,
      30000
    );
    for (const line of output.split("\n")) {
      if (!line.trim()) continue;
      let entry: any;
      try {
        entry = JSON.parse(line);
      } catch {
        continue;
      }
      if (sinceIso && entry.timestamp && entry.timestamp < sinceIso) continue;
      const message: string = entry.message || "";
      if (HTTP_UP_PATTERN(message)) {
        return { text: `✓ Server is up: ${message.trim()}` };
      }
      if (BUILD_FAILURE_PATTERN(message)) {
        return { text: `⚠️ Deploy failed: ${message.trim()}`, isError: true };
      }
    }
    await new Promise((r) => setTimeout(r, pollIntervalMs));
  }
  return {
    text: `⚠️ Timed out after ${Math.round(timeoutMs / 1000)}s waiting for the server to come back up — check \`logs\`.`,
    isError: true,
  };
}

export async function restart(config: RailwayConfig, timeoutMs = 120000): Promise<OdooResult> {
  const issuedAt = new Date().toISOString();
  try {
    railway(["restart", "-s", config.service, "-y"], config, 60000);
  } catch (error: any) {
    // `railway restart` issuing the request and Railway actually completing
    // the restart are two different things — a local CLI hang/timeout here
    // does not mean the restart didn't happen server-side. Fall through to
    // polling logs for the real confirmation instead of losing the caller's
    // (e.g. a just-completed module update's) result to a spurious throw.
    console.error(`[restart warning] issuing 'railway restart' locally failed (${error.message}) — polling logs for confirmation anyway`);
  }
  return waitForServerUp(config, timeoutMs, issuedAt);
}

export async function deploy(config: RailwayConfig, message?: string): Promise<OdooResult> {
  const issuedAt = new Date().toISOString();
  const args = ["up", "-s", config.service, "-e", config.environment, "-d"];
  if (message) args.push("-m", message);
  railway(args, config, 600000);
  return waitForServerUp(config, 300000, issuedAt);
}

async function updateOrInstall(
  config: RailwayConfig,
  modules: string,
  flag: "-u" | "-i",
  errorOnly: boolean,
  withoutDemo?: boolean
): Promise<OdooResult> {
  const dbVars = fetchDbVars(config);
  const remoteCommandParts = [
    "setpriv",
    "--reuid=odoo",
    "--regid=odoo",
    "--init-groups",
    "odoo",
    "-c",
    config.confPath,
    "--db_host",
    dbVars.host,
    "--db_port",
    dbVars.port,
    "--db_user",
    dbVars.user,
    "--db_password",
    dbVars.password,
    "-d",
    dbVars.database,
    flag,
    modules,
    "--stop-after-init",
    "--no-http",
    "--log-level=warn",
  ];
  if (withoutDemo) remoteCommandParts.push("--without-demo=all");

  // Pass remoteCommandParts as discrete argv entries directly after `--`,
  // NOT joined into one pre-quoted string for `sh -c`. `railway ssh --
  // sh -c '<big string>'` looks right locally, but `sh -c` only ever
  // treats its FIRST argument as the script — every remaining word
  // (even individually single-quoted) becomes an ignored positional
  // parameter ($0, $1, ...), so the real command (setpriv/odoo-bin with
  // all its flags) never actually ran; only the bare first token did.
  // Confirmed by direct reproduction: `railway ssh -- sh -c "'echo'
  // 'hello world'"` prints nothing but a blank line, while `railway ssh
  // -- echo hello world` (flat argv, no wrapper) prints "hello world"
  // correctly — `railway ssh --` already forwards each subsequent argv
  // item as its own distinct remote argument, so no shell/quoting layer
  // is needed at all. This silently no-op'd every update/install call
  // all session, always reporting false success (empty stdout has no
  // error-pattern lines, so the "no errors" check passed vacuously).
  let output: string;
  try {
    output = execFileSync(
      "railway",
      ["ssh", "-s", config.service, "-e", config.environment, "--", ...remoteCommandParts],
      { cwd: config.dir, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024, timeout: 300000 }
    );
  } catch (error: any) {
    output = (error.stdout || "") + (error.stderr ? `\n\n=== STDERR ===\n${error.stderr}` : "");
    if (!output) throw new Error(`railway ssh update failed: ${error.message}`);
  }

  const filtered = filterOdooOutput(output, errorOnly);
  const verb = flag === "-u" ? "updated" : "installed";
  if (filtered.startsWith("⚠️ ERRORS FOUND")) {
    return { text: `Modules NOT ${verb} (errors during migration, server left untouched): ${modules}\n${filtered}`, isError: true };
  }

  let restartResult: OdooResult;
  try {
    restartResult = await restart(config);
  } catch (error: any) {
    // The migration itself already succeeded (we only get here when `filtered`
    // reported no errors) — never let a restart-side failure erase that result.
    return {
      text: `Modules ${verb}: ${modules}\n${filtered}\n\n⚠️ Restart step threw: ${error.message}\nThe migration completed; check \`status\`/\`logs\` to confirm the server came back up.`,
      isError: true,
    };
  }
  if (restartResult.isError) {
    return { text: `Modules ${verb}: ${modules}\n${filtered}\n\nRestart did not confirm cleanly:\n${restartResult.text}`, isError: true };
  }
  return { text: `Modules ${verb}: ${modules}\n${filtered}\n\n${restartResult.text}` };
}

export function updateModules(config: RailwayConfig, modules: string, errorOnly: boolean, withoutDemo?: boolean): Promise<OdooResult> {
  return updateOrInstall(config, modules, "-u", errorOnly, withoutDemo);
}

export function installModules(config: RailwayConfig, modules: string, errorOnly: boolean, withoutDemo?: boolean): Promise<OdooResult> {
  return updateOrInstall(config, modules, "-i", errorOnly, withoutDemo);
}

export function getStatus(config: RailwayConfig): OdooResult {
  const status = railway(["status", "--json"], config);
  let recentUp = "unknown";
  try {
    const logsOutput = railway(["logs", "-s", config.service, "-e", config.environment, "-n", "30", "--json"], config, 30000);
    for (const line of logsOutput.split("\n")) {
      if (!line.trim()) continue;
      try {
        const entry = JSON.parse(line);
        if (HTTP_UP_PATTERN(entry.message || "")) {
          recentUp = `confirmed up as of ${entry.timestamp}`;
          break;
        }
      } catch {
        // skip
      }
    }
  } catch {
    // status still useful without the log check
  }
  return { text: `${status}\nRecent server-up check: ${recentUp}` };
}

export function getLogs(config: RailwayConfig, lines: number): OdooResult {
  const output = railway(["logs", "-s", config.service, "-e", config.environment, "-n", String(lines)], config, 30000);
  return { text: output };
}

export function sshPassthrough(config: RailwayConfig, command: string[]): OdooResult {
  const args = ["ssh", "-s", config.service, "-e", config.environment];
  if (command.length) args.push("--", ...command);
  const output = railway(args, config, 300000);
  return { text: output };
}

export function getVariables(config: RailwayConfig): OdooResult {
  const output = railway(["variable", "list", "-s", config.service, "-e", config.environment, "--json"], config);
  const vars = JSON.parse(output);
  const masked = Object.fromEntries(
    Object.entries(vars).map(([k, v]) => [k, /password|secret|token|key/i.test(k) ? "***" : v])
  );
  return { text: JSON.stringify(masked, null, 2) };
}
