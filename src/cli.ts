#!/usr/bin/env node

// CLI entry point for the Odoo management logic in core.ts. This is what the
// Claude Code skill calls (node build/cli.js <command> ...), so the same logic
// and output filtering used by the MCP server is available without running a
// connected MCP server. Prints OdooResult.text to stdout and exits non-zero on
// error results.

import * as odoo from "./core.js";

interface ParsedArgs {
  command: string;
  positionals: string[];
  errorOnly: boolean;
  tags?: string;
  lines?: number;
  base?: string;
  dbOnly: boolean;
  filestoreOnly: boolean;
  neutralize: boolean;
  noStart: boolean;
  remoteDb?: string;
  remoteDataDir?: string;
  init?: string;
  odooVersion?: string;
  enterprise: boolean;
  modules?: string;
  repo?: string;
  httpPort?: string;
  force: boolean;
}

function parseArgs(argv: string[]): ParsedArgs {
  const positionals: string[] = [];
  let errorOnly = false;
  let tags: string | undefined;
  let lines: number | undefined;
  let base: string | undefined;
  let dbOnly = false;
  let filestoreOnly = false;
  let neutralize = false;
  let noStart = false;
  let remoteDb: string | undefined;
  let remoteDataDir: string | undefined;
  let init: string | undefined;
  let odooVersion: string | undefined;
  let enterprise = false;
  let modules: string | undefined;
  let repo: string | undefined;
  let httpPort: string | undefined;
  let force = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--error-only") {
      errorOnly = true;
    } else if (arg === "--tags") {
      tags = argv[++i];
    } else if (arg === "--lines") {
      lines = parseInt(argv[++i], 10);
    } else if (arg === "--base") {
      base = argv[++i];
    } else if (arg === "--db-only") {
      dbOnly = true;
    } else if (arg === "--filestore-only") {
      filestoreOnly = true;
    } else if (arg === "--neutralize") {
      neutralize = true;
    } else if (arg === "--no-start") {
      noStart = true;
    } else if (arg === "--remote-db") {
      remoteDb = argv[++i];
    } else if (arg === "--remote-data-dir") {
      remoteDataDir = argv[++i];
    } else if (arg === "--init") {
      init = argv[++i];
    } else if (arg === "--version") {
      odooVersion = argv[++i];
    } else if (arg === "--enterprise") {
      enterprise = true;
    } else if (arg === "--modules") {
      modules = argv[++i];
    } else if (arg === "--repo") {
      repo = argv[++i];
    } else if (arg === "--http-port") {
      httpPort = argv[++i];
    } else if (arg === "--force") {
      force = true;
    } else if (arg.startsWith("--")) {
      throw new Error(`Unknown option: ${arg}`);
    } else {
      positionals.push(arg);
    }
  }

  const command = positionals.shift() || "help";
  return { command, positionals, errorOnly, tags, lines, base, dbOnly, filestoreOnly, neutralize, noStart, remoteDb, remoteDataDir, init, odooVersion, enterprise, modules, repo, httpPort, force };
}

const HELP = `Odoo management CLI

Usage: odoo-cli <command> [args] [options]

Commands:
  start                      Start the Odoo server
  stop                       Stop the Odoo server
  restart                    Restart the Odoo server
  status                     Check if Odoo is running
  update <modules>           Update module(s) (comma-separated) and restart
  install <modules>          Install module(s) (comma-separated)
  frontend <modules>         Update frontend module(s) and restart
  test [modules]             Run tests (all, or for given module(s))
  shell                      Print the command to open an interactive Odoo shell
  switch <project>           Switch to project config (odoo-<project>.conf) and restart
  new <name>                 Scaffold a new project (config + addons symlink + DB + modules), then switch to it
  list                       List available project configurations
  import <file>              Import a backup into the active DB (.zip/.sql/.sql.gz/.dump), then restart
  fresh                      Drop the active DB+filestore and create an empty database, then restart
  stream <host>              Stream a remote nellika.sh/tcff Odoo db+filestore (over SSH) into the active project, then restart
  logs                       Show the tail of odoo.log
  project-dir <project>      Show a project's custom addons directory
  addons-dir                 Show the active Odoo core addons directory
  enterprise-dir             Show the active Odoo Enterprise addons directory
  config-path                Show the active odoo.conf path
  project-config <project>   Show a project's odoo-<project>.conf path

Options:
  --error-only               Suppress warnings, show only errors (update/install/frontend/test)
  --tags <tags>              Test tags filter (test command)
  --lines <n>                Number of log lines (logs command, default 50)
  --base <path|name>         Base directory (default: $HOME/odoo, fallback ~/git/odoo18)
  --db-only                  (import/stream) restore database only, skip filestore
  --filestore-only           (stream) stream the filestore only, skip the database
  --remote-db <name>         (stream) override the auto-discovered remote db name
  --remote-data-dir <path>   (stream) override the auto-discovered remote data_dir
  --neutralize               (import/stream) neutralize the DB after restore (disable mail/crons/payments)
  --no-start                 (import/fresh/new/stream) do not start Odoo afterwards
  --init <modules>           (fresh) initialize the empty DB with these modules
  --version <18|19>          (new) Odoo version for the project (default 18)
  --enterprise               (new) include the enterprise addons in the config
  --modules <a,b,c>          (new) modules to install in the new project
  --repo <path>              (new) symlink ./<name> to this repo (default ~/git/<name>)
  --http-port <n>            (new) http_port for the project (default 8069)
  --force                    (new) overwrite an existing odoo-<name>.conf
`;

function run(): odoo.OdooResult {
  const { command, positionals, errorOnly, tags, lines, base, dbOnly, filestoreOnly, neutralize, noStart,
          remoteDb, remoteDataDir, init,
          odooVersion, enterprise, modules, repo, httpPort, force } =
    parseArgs(process.argv.slice(2));

  if (command === "help" || command === "--help" || command === "-h") {
    return { text: HELP };
  }

  const config = odoo.resolveConfig(base);

  switch (command) {
    case "start":
      return odoo.startOdoo(config);
    case "stop":
      return odoo.stopOdoo(config);
    case "restart":
      return odoo.restartOdoo(config);
    case "status":
      return odoo.checkStatus(config);
    case "update":
      if (!positionals[0]) throw new Error("update requires a module list");
      return odoo.updateModules(config, positionals[0], errorOnly);
    case "install":
      if (!positionals[0]) throw new Error("install requires a module list");
      return odoo.installModules(config, positionals[0], errorOnly);
    case "frontend":
      if (!positionals[0]) throw new Error("frontend requires a module list");
      return odoo.updateFrontend(config, positionals[0], errorOnly);
    case "test":
      return odoo.runTests(config, positionals[0], tags, errorOnly);
    case "shell":
      return odoo.startShell(config);
    case "switch":
      if (!positionals[0]) throw new Error("switch requires a project name");
      return odoo.switchDatabase(config, positionals[0]);
    case "new":
      if (!positionals[0]) throw new Error("new requires a project name");
      return odoo.newProject(config, positionals[0], {
        version: odooVersion,
        enterprise,
        modules,
        repo,
        httpPort,
        noStart,
        force,
      });
    case "list":
      return odoo.listDatabases(config);
    case "import":
      if (!positionals[0]) throw new Error("import requires a backup file path");
      return odoo.importDatabase(config, positionals[0], { dbOnly, neutralize, noStart });
    case "fresh":
      return odoo.createFreshDb(config, { init, noStart });
    case "stream":
      if (!positionals[0]) throw new Error("stream requires a remote ssh host");
      return odoo.streamDatabase(config, positionals[0], {
        remoteDb, remoteDataDir, dbOnly, filestoreOnly, neutralize, noStart,
      });
    case "logs":
      return odoo.getLogs(config, lines || 50);
    case "project-dir":
      if (!positionals[0]) throw new Error("project-dir requires a project name");
      return odoo.getProjectDir(config, positionals[0]);
    case "addons-dir":
      return odoo.getOdooAddonDir(config);
    case "enterprise-dir":
      return odoo.getEnterpriseDir(config);
    case "config-path":
      return odoo.getConfigPath(config);
    case "project-config":
      if (!positionals[0]) throw new Error("project-config requires a project name");
      return odoo.getProjectConfigPath(config, positionals[0]);
    default:
      throw new Error(`Unknown command: ${command}\n\n${HELP}`);
  }
}

try {
  const result = run();
  console.log(result.text);
  process.exit(result.isError ? 1 : 0);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Error: ${message}`);
  process.exit(1);
}
