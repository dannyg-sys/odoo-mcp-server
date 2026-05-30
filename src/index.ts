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

SERVER CONTROL:
- "Start Odoo" - Start the Odoo server
- "Stop Odoo" - Stop the Odoo server
- "Restart Odoo" - Restart the Odoo server
- "Check Odoo status" - See if Odoo is running

MODULE MANAGEMENT:
- "Update [module_name]" - Update specific modules
- "Install [module_name]" - Install new modules
- "Update frontend [module_name]" - Update frontend and restart

DATABASE:
- "Switch to [project] database" - Switch database configuration
- "List databases" - Show available database configs

DIRECTORIES:
- "Where is the [project] directory?" - Get project addon path
- "Where is the Odoo core directory?" - Get core addons path
- "Where is the enterprise directory?" - Get enterprise addons path

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
        description: "Update one or more Odoo modules",
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
        description: "Update a single Odoo module (alias for odoo_update_modules)",
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
        description: "Install one or more Odoo modules",
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
        description: "Update frontend modules and automatically restart Odoo",
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
        description: "Switch between different Odoo database configurations",
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
        description: "List available database configurations",
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
        description: "Import an Odoo database backup (.zip file)",
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
              description: "Path to the backup .zip file"
            }
          },
          required: ["backupFile"]
        }
      },
      {
        name: "odoo_get_logs",
        description: "Get the last N lines from Odoo logs",
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
        description: "Get the path to a project's custom addon directory (e.g., ~/git/odoo18/<project>). This is usually a symlink to ~/git/<project>",
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
        description: "Get the path to the Odoo core addons directory (~/git/odoo18/odoo)",
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
        description: "Get the path to the Odoo Enterprise addons directory (~/git/odoo18/enterprise)",
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
        description: "Get the path to the active Odoo configuration file (~/git/odoo18/odoo.conf)",
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
        description: "Get the path to a project-specific Odoo configuration file (~/git/odoo18/<project>.conf)",
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
        return odoo.importDatabase(config, args.backupFile);
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
