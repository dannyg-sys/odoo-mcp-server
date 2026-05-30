#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as odoo from "./core.js";
import { OdooResult } from "./core.js";

class OdooMCPServer {
  private server: Server;

  constructor() {
    this.server = new Server(
      {
        name: "odoo-mcp-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {},
          prompts: {},
        },
      }
    );

    this.setupHandlers();

    // Error handling
    this.server.onerror = (error) => {
      console.error("[MCP Error]", error);
    };

    // Handle uncaught errors
    process.on("uncaughtException", (error) => {
      console.error("[Uncaught Exception]", error);
      // Don't exit - keep server running
    });

    process.on("unhandledRejection", (reason, promise) => {
      console.error("[Unhandled Rejection]", reason);
      // Don't exit - keep server running
    });

    process.on("SIGINT", async () => {
      console.error("[Shutting down]");
      await this.server.close();
      process.exit(0);
    });

    process.on("SIGTERM", async () => {
      console.error("[Shutting down]");
      await this.server.close();
      process.exit(0);
    });
  }

  private setupHandlers() {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: this.getTools(),
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      try {
        const result = this.handleToolCall(request.params.name, request.params.arguments);
        return {
          content: [{ type: "text", text: result.text }],
          ...(result.isError ? { isError: true } : {}),
        };
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        return {
          content: [
            {
              type: "text",
              text: `Error: ${errorMessage}`,
            },
          ],
          isError: true,
        };
      }
    });

    this.server.setRequestHandler(ListPromptsRequestSchema, async () => ({
      prompts: [
        {
          name: "odoo-help",
          description: "Get help with Odoo management commands",
        },
      ],
    }));

    this.server.setRequestHandler(GetPromptRequestSchema, async (request) => {
      if (request.params.name === "odoo-help") {
        return {
          messages: [
            {
              role: "user",
              content: {
                type: "text",
                text: `I can help you manage Odoo development environments. Here are the available commands:

ENVIRONMENT LAYOUT (read this first)
- Base directory (fixed): ~/odoo — holds the active odoo.conf and one
  odoo-<project>.conf per project. (The engine manage_odoo.sh is installed
  globally, not in the base.)
- Odoo sources live INSIDE the base, _-prefixed so they stand out from the
  unprefixed project addon symlinks: _odoo18/ (CE 18), _enterprise18/ (EE 18),
  _odoo19/ (CE 19), _enterprise19/ (EE 19), plus _venv18/, _venv19/, and _data/.
- 18 vs 19 is per-PROJECT, not a separate tree. The active odoo.conf selects it
  via its "; odoo_src" / "; python_venv" markers and addons_path. Switching the
  project is what changes the running version — there is no version flag to set.
  Use odoo_info (action=addons-dir) to see which one is active (a path under
  _odoo19/ means CE 19).

TOOLS: everything is grouped into four tools, each taking an "action":
  odoo_server  (start|stop|restart|status|shell)
  odoo_modules (update|install|frontend|test; 'modules', 'errorOnly')
  odoo_project (list|switch|new|import|fresh; 'project'/'name'/'backupFile'/…)
  odoo_info    (logs|config-path|project-config|project-dir|addons-dir|enterprise-dir)

SERVER CONTROL:
- "Start Odoo" - Start the Odoo server
- "Stop Odoo" - Stop the Odoo server
- "Restart Odoo" - Restart the Odoo server
- "Check Odoo status" - See if Odoo is running

MODULE MANAGEMENT:
- "Update [module_name]" - Update specific modules and restart
- "Install [module_name]" - Install new modules
- "Update frontend [module_name]" - Update frontend and restart
Note: update/install/frontend output is filtered to errors and warnings
(a clean run reports "✓ completed"). To see the full unfiltered log use
odoo_info (action=logs).

TESTING:
- "Run tests [for module]" - Run module tests (optionally by test tags)

DATABASE / PROJECTS:
- "Switch to [project] database" - Activate odoo-<project>.conf and restart.
  This ALSO changes which Odoo version (18/19) runs, per that conf.
- "List databases" - Show available project configs and the active one

DIRECTORIES:
- "Where is the [project] directory?" - Get project addon path
- "Where is the Odoo core directory?" - Get active core addons path (_odoo18/ or _odoo19/)
- "Where is the enterprise directory?" - Get active enterprise path (_enterprise18/ or _enterprise19/)

Use any of these commands naturally and I'll use the Odoo management tools to help you!`,
              },
            },
          ],
        };
      }
      throw new Error(`Unknown prompt: ${request.params.name}`);
    });
  }

  private getTools(): Tool[] {
    return [
      {
        name: "odoo_server",
        description: "Control the Odoo server for the active project. action: start | stop | restart | status | shell (shell prints the command to open an interactive shell).",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["start", "stop", "restart", "status", "shell"], description: "What to do" }
          },
          required: ["action"]
        }
      },
      {
        name: "odoo_modules",
        description: "Update/install/test Odoo modules in the active project. action: update | install | frontend | test. 'modules' is a comma-separated list (required for update/install/frontend; optional for test = all). Output is filtered to errors/warnings; use odoo_info action=logs for the full log.",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["update", "install", "frontend", "test"], description: "What to do" },
            modules: { type: "string", description: "Comma-separated modules (e.g. 'sale,account'); optional for test" },
            testTags: { type: "string", description: "Test tags filter (test only), e.g. 'at_install'" },
            errorOnly: { type: "boolean", description: "Suppress warnings, show only errors", default: false }
          },
          required: ["action"]
        }
      },
      {
        name: "odoo_project",
        description: "Manage projects and their databases. action: list (projects + active one) | switch (activate odoo-<project>.conf and restart; also changes the running Odoo 18/19) | new (scaffold a new project) | import (load a backup into the active DB) | fresh (reset the active DB to empty). DESTRUCTIVE: import/fresh drop the active DB; new creates/recreates the named DB.",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["list", "switch", "new", "import", "fresh"], description: "What to do" },
            project: { type: "string", description: "Project name (switch)" },
            name: { type: "string", description: "New project name (new) — used for odoo-<name>.conf, the database, and the ./<name> addons symlink" },
            odooVersion: { type: "string", enum: ["18", "19"], description: "Odoo version for a new project (new)", default: "18" },
            enterprise: { type: "boolean", description: "Include enterprise addons (new)", default: false },
            modules: { type: "string", description: "Comma-separated modules to install (new) or initialize (fresh), e.g. 'sale,account,stock'" },
            repo: { type: "string", description: "Path to symlink ./<name> at (new; default ~/git/<name>)" },
            httpPort: { type: "number", description: "http_port for a new project (new; default 8069)" },
            backupFile: { type: "string", description: "Backup file path (import): .zip / .sql / .sql.gz / .dump" },
            dbOnly: { type: "boolean", description: "Restore DB only, skip filestore (import)", default: false },
            neutralize: { type: "boolean", description: "Neutralize the DB after import (disable mail/crons/payments)", default: false },
            noStart: { type: "boolean", description: "Do not start Odoo afterwards (new/import/fresh)", default: false }
          },
          required: ["action"]
        }
      },
      {
        name: "odoo_info",
        description: "Inspect the active project. action: logs (tail the full odoo.log) | config-path | project-config | project-dir | addons-dir (active core source: _odoo18 or _odoo19) | enterprise-dir.",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["logs", "config-path", "project-config", "project-dir", "addons-dir", "enterprise-dir"], description: "What to inspect" },
            project: { type: "string", description: "Project name (project-config / project-dir)" },
            lines: { type: "number", description: "Number of log lines (logs)", default: 50 }
          },
          required: ["action"]
        }
      }
    ];
  }

  private handleToolCall(name: string, args: any): OdooResult {
    args = args || {};
    const config = odoo.resolveConfig();
    const action: string = args.action;

    const need = (v: any, label: string) => {
      if (v === undefined || v === null || v === "") {
        throw new Error(`${name} action '${action}' requires '${label}'`);
      }
    };

    switch (name) {
      case "odoo_server":
        switch (action) {
          case "start": return odoo.startOdoo(config);
          case "stop": return odoo.stopOdoo(config);
          case "restart": return odoo.restartOdoo(config);
          case "status": return odoo.checkStatus(config);
          case "shell": return odoo.startShell(config);
        }
        break;
      case "odoo_modules":
        switch (action) {
          case "update": need(args.modules, "modules"); return odoo.updateModules(config, args.modules, args.errorOnly);
          case "install": need(args.modules, "modules"); return odoo.installModules(config, args.modules, args.errorOnly);
          case "frontend": need(args.modules, "modules"); return odoo.updateFrontend(config, args.modules, args.errorOnly);
          case "test": return odoo.runTests(config, args.modules, args.testTags, args.errorOnly);
        }
        break;
      case "odoo_project":
        switch (action) {
          case "list": return odoo.listDatabases(config);
          case "switch": need(args.project, "project"); return odoo.switchDatabase(config, args.project);
          case "new":
            need(args.name, "name");
            return odoo.newProject(config, args.name, {
              version: args.odooVersion, enterprise: args.enterprise, modules: args.modules,
              repo: args.repo, httpPort: args.httpPort, noStart: args.noStart,
            });
          case "import":
            need(args.backupFile, "backupFile");
            return odoo.importDatabase(config, args.backupFile, {
              dbOnly: args.dbOnly, neutralize: args.neutralize, noStart: args.noStart,
            });
          case "fresh": return odoo.createFreshDb(config, { init: args.modules, noStart: args.noStart });
        }
        break;
      case "odoo_info":
        switch (action) {
          case "logs": return odoo.getLogs(config, args.lines || 50);
          case "config-path": return odoo.getConfigPath(config);
          case "project-config": need(args.project, "project"); return odoo.getProjectConfigPath(config, args.project);
          case "project-dir": need(args.project, "project"); return odoo.getProjectDir(config, args.project);
          case "addons-dir": return odoo.getOdooAddonDir(config);
          case "enterprise-dir": return odoo.getEnterpriseDir(config);
        }
        break;
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
    throw new Error(`${name}: unknown or missing action '${action}'`);
  }

  async run() {
    try {
      const transport = new StdioServerTransport();
      await this.server.connect(transport);
      console.error("Odoo MCP Server running on stdio");
    } catch (error) {
      console.error("Failed to start MCP server:", error);
      process.exit(1);
    }
  }
}

// Graceful startup
const server = new OdooMCPServer();
server.run().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
