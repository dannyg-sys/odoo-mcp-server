#!/usr/bin/env node

// CLI entry point for the Railway-Odoo management logic in railway-core.ts.
// This is what the railway-odoo skill calls (node build/railway-cli.js
// <command> ...). Run from inside the target project's directory (e.g.
// ~/git/faceline) so `railway`'s own directory-based project/service linking
// resolves correctly. Prints OdooResult.text to stdout and exits non-zero on
// error results.

import * as railwayOdoo from "./railway-core.js";

interface ParsedArgs {
  command: string;
  positionals: string[];
  errorOnly: boolean;
  withoutDemo: boolean;
  lines?: number;
  message?: string;
}

function parseArgs(argv: string[]): ParsedArgs {
  const positionals: string[] = [];
  let errorOnly = false;
  let withoutDemo = false;
  let lines: number | undefined;
  let message: string | undefined;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--error-only") {
      errorOnly = true;
    } else if (arg === "--without-demo") {
      withoutDemo = true;
    } else if (arg === "--lines") {
      lines = parseInt(argv[++i], 10);
    } else if (arg === "--message") {
      message = argv[++i];
    } else if (arg === "--") {
      // Everything after a bare "--" is passed through verbatim (used by `ssh`).
      positionals.push(...argv.slice(i + 1));
      break;
    } else if (arg.startsWith("--")) {
      throw new Error(`Unknown option: ${arg}`);
    } else {
      positionals.push(arg);
    }
  }

  const command = positionals.shift() || "help";
  return { command, positionals, errorOnly, withoutDemo, lines, message };
}

const HELP = `Railway-Odoo management CLI

Usage: railway-odoo-cli <command> [args] [options]
Run from inside the target project's directory (e.g. ~/git/faceline).

Commands:
  update <modules>    Update module(s) (comma-separated) inside the running
                       container via 'railway ssh', then restart — filtered output
  install <modules>   Install module(s) the same way
  deploy              Full 'railway up' rebuild — for actual code changes
  restart             Fast restart (no rebuild)
  status              Project/service status + recent server-up check
  logs                Unfiltered log passthrough
  ssh [-- COMMAND...] Passthrough to 'railway ssh' (interactive if no COMMAND)
  variables           List Railway variables for the service (secrets masked)

Options:
  --error-only        Suppress warnings, show only errors (update/install)
  --without-demo      Skip demo data for newly installed modules (update/install)
  --lines <n>         Number of log lines (logs command, default 50)
  --message <m>       Deployment message (deploy command)
`;

async function run(): Promise<railwayOdoo.OdooResult> {
  const { command, positionals, errorOnly, withoutDemo, lines, message } = parseArgs(process.argv.slice(2));

  if (command === "help" || command === "--help" || command === "-h") {
    return { text: HELP };
  }

  const config = railwayOdoo.resolveRailwayConfig(process.cwd());

  switch (command) {
    case "update":
      if (!positionals[0]) throw new Error("update requires a module list");
      return railwayOdoo.updateModules(config, positionals[0], errorOnly, withoutDemo);
    case "install":
      if (!positionals[0]) throw new Error("install requires a module list");
      return railwayOdoo.installModules(config, positionals[0], errorOnly, withoutDemo);
    case "deploy":
      return railwayOdoo.deploy(config, message);
    case "restart":
      return railwayOdoo.restart(config);
    case "status":
      return railwayOdoo.getStatus(config);
    case "logs":
      return railwayOdoo.getLogs(config, lines || 50);
    case "ssh":
      return railwayOdoo.sshPassthrough(config, positionals);
    case "variables":
      return railwayOdoo.getVariables(config);
    default:
      throw new Error(`Unknown command: ${command}\n\n${HELP}`);
  }
}

run()
  .then((result) => {
    console.log(result.text);
    process.exit(result.isError ? 1 : 0);
  })
  .catch((error) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Error: ${message}`);
    process.exit(1);
  });
