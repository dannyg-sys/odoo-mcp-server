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
  Use odoo_get_odoo_addon_dir to see which one is active (a path under _odoo19/
  means CE 19).

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
odoo_get_logs.

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
        name: "odoo_start",
        description: "Start the Odoo server. Use this when the user asks to start Odoo, launch Odoo, or run Odoo.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_stop",
        description: "Stop the running Odoo server. Use this when the user asks to stop Odoo, shutdown Odoo, or kill Odoo.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_restart",
        description: "Restart the Odoo server. Use this when the user asks to restart Odoo, reboot Odoo, or reload Odoo.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_status",
        description: "Check if Odoo server is running",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_update_modules",
        description: "Update one or more Odoo modules and restart. Output is filtered to errors and warnings (a clean run reports success); set errorOnly to suppress warnings too, or use odoo_get_logs for the full unfiltered log.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            modules: {
              type: "string",
              description: "Comma-separated list of modules to update (e.g., 'sale,purchase')"
            },
            errorOnly: {
              type: "boolean",
              description: "Show only error output",
              default: false
            }
          },
          required: ["modules"]
        }
      },
      {
        name: "odoo_update_module",
        description: "Update a single Odoo module and restart (alias for odoo_update_modules). Output is filtered to errors and warnings; use odoo_get_logs for the full log.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            module: {
              type: "string",
              description: "Module name to update (e.g., 'sale' or 'purchase')"
            },
            errorOnly: {
              type: "boolean",
              description: "Show only error output",
              default: false
            }
          },
          required: ["module"]
        }
      },
      {
        name: "odoo_install_modules",
        description: "Install one or more Odoo modules. Output is filtered to errors and warnings; set errorOnly to suppress warnings, or use odoo_get_logs for the full log.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            modules: {
              type: "string",
              description: "Comma-separated list of modules to install (e.g., 'stock_account,hr')"
            },
            errorOnly: {
              type: "boolean",
              description: "Show only error output",
              default: false
            }
          },
          required: ["modules"]
        }
      },
      {
        name: "odoo_update_frontend",
        description: "Update frontend modules and automatically restart Odoo. Output is filtered to errors and warnings; use odoo_get_logs for the full log.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            modules: {
              type: "string",
              description: "Comma-separated list of frontend modules to update"
            },
            errorOnly: {
              type: "boolean",
              description: "Show only error output",
              default: false
            }
          },
          required: ["modules"]
        }
      },
      {
        name: "odoo_run_tests",
        description: "Run tests for Odoo modules",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            modules: {
              type: "string",
              description: "Comma-separated list of modules to test (empty for all tests)"
            },
            testTags: {
              type: "string",
              description: "Test tags to filter tests (e.g., 'at_install', 'post_install')"
            },
            errorOnly: {
              type: "boolean",
              description: "Show only error output",
              default: false
            }
          }
        }
      },
      {
        name: "odoo_shell",
        description: "Start interactive Odoo shell",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_switch_database",
        description: "Switch the active project by copying odoo-<project>.conf to odoo.conf and restarting. IMPORTANT: this also changes which Odoo version (18 or 19) runs, because the version is determined by the project's conf (odoo_src/python_venv/addons_path). Use odoo_list_databases to see available projects.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            project: {
              type: "string",
              description: "Project name (e.g., 'hhfbs', 'tora', 'nellika')"
            }
          },
          required: ["project"]
        }
      },
      {
        name: "odoo_list_databases",
        description: "List available project configurations (odoo-<project>.conf) and the currently active database. Each project maps to one config; use odoo_switch_database to activate one.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_import_database",
        description: "Import a backup into the ACTIVE project's database, then restart Odoo. Auto-detects format: Odoo/odoo.sh .zip (dump.sql [+ filestore]), plain .sql, gzipped .sql.gz/.gz, or pg_dump custom .dump. WARNING: destructive — this DROPS and recreates the active database.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            backupFile: {
              type: "string",
              description: "Path to the backup file (.zip, .sql, .sql.gz/.gz, or .dump)"
            },
            dbOnly: {
              type: "boolean",
              description: "Restore the database only, skip the filestore even if present in the zip",
              default: false
            },
            neutralize: {
              type: "boolean",
              description: "Neutralize the database after restore (disable outgoing mail, crons, payment providers) — use for production/odoo.sh exact backups",
              default: false
            },
            noStart: {
              type: "boolean",
              description: "Do not start Odoo after the import",
              default: false
            }
          },
          required: ["backupFile"]
        }
      },
      {
        name: "odoo_create_fresh_db",
        description: "Create a FRESH (empty) database for the ACTIVE project, then restart Odoo (an empty database initializes the base modules on startup). WARNING: destructive — this DROPS the active database and removes its filestore.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            initModules: {
              type: "string",
              description: "Optional comma-separated modules to initialize the empty DB with (e.g., 'base,sale')"
            },
            noStart: {
              type: "boolean",
              description: "Do not start Odoo after creating the fresh database",
              default: false
            }
          }
        }
      },
      {
        name: "odoo_get_logs",
        description: "Get the last N lines from the full, unfiltered odoo.log. Use this to see complete output that the filtered update/install/frontend tools omit.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            lines: {
              type: "number",
              description: "Number of lines to retrieve",
              default: 50
            }
          }
        }
      },
      {
        name: "odoo_get_project_dir",
        description: "Get the path to a project's custom addon directory (e.g., ~/odoo/<project>). This is usually a symlink to ~/git/<project>",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            project: {
              type: "string",
              description: "Project name (e.g., 'hhfbs', 'tora', 'nellika')"
            }
          },
          required: ["project"]
        }
      },
      {
        name: "odoo_get_odoo_addon_dir",
        description: "Get the active Odoo core addons directory, read from the current odoo.conf addons_path. Resolves to _odoo18/ (CE 18) or _odoo19/ (CE 19) depending on the active project — use this to tell which version is running.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_get_enterprise_dir",
        description: "Get the active Odoo Enterprise addons directory, read from the current odoo.conf addons_path. Resolves to _enterprise18/ (EE 18) or _enterprise19/ (EE 19) depending on the active project.",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_get_config_path",
        description: "Get the path to the active Odoo configuration file (~/odoo/odoo.conf)",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            }
          }
        }
      },
      {
        name: "odoo_get_project_config_path",
        description: "Get the path to a project-specific Odoo configuration file (~/odoo/odoo-<project>.conf)",
        inputSchema: {
          type: "object",
          properties: {
            version: {
              type: "string",
              description: "Odoo version (e.g., 'odoo18')",
              default: "odoo18"
            },
            project: {
              type: "string",
              description: "Project name (e.g., 'hhfbs', 'tora', 'nellika')"
            }
          },
          required: ["project"]
        }
      }
    ];
  }

  private handleToolCall(name: string, args: any): OdooResult {
    args = args || {};
    const config = odoo.resolveConfig(args.version);

    switch (name) {
      case "odoo_start":
        return odoo.startOdoo(config);
      case "odoo_stop":
        return odoo.stopOdoo(config);
      case "odoo_restart":
        return odoo.restartOdoo(config);
      case "odoo_status":
        return odoo.checkStatus(config);
      case "odoo_update_modules":
        return odoo.updateModules(config, args.modules, args.errorOnly);
      case "odoo_update_module":
        return odoo.updateModules(config, args.module, args.errorOnly);
      case "odoo_install_modules":
        return odoo.installModules(config, args.modules, args.errorOnly);
      case "odoo_update_frontend":
        return odoo.updateFrontend(config, args.modules, args.errorOnly);
      case "odoo_run_tests":
        return odoo.runTests(config, args.modules, args.testTags, args.errorOnly);
      case "odoo_shell":
        return odoo.startShell(config);
      case "odoo_switch_database":
        return odoo.switchDatabase(config, args.project);
      case "odoo_list_databases":
        return odoo.listDatabases(config);
      case "odoo_import_database":
        return odoo.importDatabase(config, args.backupFile, {
          dbOnly: args.dbOnly,
          neutralize: args.neutralize,
          noStart: args.noStart,
        });
      case "odoo_create_fresh_db":
        return odoo.createFreshDb(config, {
          init: args.initModules,
          noStart: args.noStart,
        });
      case "odoo_get_logs":
        return odoo.getLogs(config, args.lines || 50);
      case "odoo_get_project_dir":
        return odoo.getProjectDir(config, args.project);
      case "odoo_get_odoo_addon_dir":
        return odoo.getOdooAddonDir(config);
      case "odoo_get_enterprise_dir":
        return odoo.getEnterpriseDir(config);
      case "odoo_get_config_path":
        return odoo.getConfigPath(config);
      case "odoo_get_project_config_path":
        return odoo.getProjectConfigPath(config, args.project);
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
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
