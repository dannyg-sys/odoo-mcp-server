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
import { execSync } from "child_process";
import { existsSync, readFileSync, readdirSync } from "fs";
import { join } from "path";
import os from "os";

interface OdooConfig {
  root: string;
  name: string;
}

// Default configurations
const DEFAULT_CONFIGS: Record<string, OdooConfig> = {
  odoo18: {
    root: join(os.homedir(), "git", "odoo18"),
    name: "Odoo 18"
  }
};

class OdooMCPServer {
  private server: Server;
  private configs: Record<string, OdooConfig>;

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

    this.configs = { ...DEFAULT_CONFIGS };

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
        return await this.handleToolCall(request.params.name, request.params.arguments);
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

  private async handleToolCall(name: string, args: any): Promise<any> {
    const version = args.version || "odoo18";
    const config = this.configs[version];

    if (!config) {
      throw new Error(`Unknown Odoo version: ${version}. Available versions: ${Object.keys(this.configs).join(", ")}`);
    }

    if (!existsSync(config.root)) {
      throw new Error(`Odoo root directory not found: ${config.root}`);
    }

    switch (name) {
      case "odoo_start":
        return this.startOdoo(config);
      case "odoo_stop":
        return this.stopOdoo(config);
      case "odoo_restart":
        return this.restartOdoo(config);
      case "odoo_status":
        return this.checkStatus(config);
      case "odoo_update_modules":
        return this.updateModules(config, args.modules, args.errorOnly);
      case "odoo_update_module":
        return this.updateModules(config, args.module, args.errorOnly);
      case "odoo_install_modules":
        return this.installModules(config, args.modules, args.errorOnly);
      case "odoo_update_frontend":
        return this.updateFrontend(config, args.modules, args.errorOnly);
      case "odoo_run_tests":
        return this.runTests(config, args.modules, args.testTags, args.errorOnly);
      case "odoo_shell":
        return this.startShell(config);
      case "odoo_switch_database":
        return this.switchDatabase(config, args.project);
      case "odoo_list_databases":
        return this.listDatabases(config);
      case "odoo_import_database":
        return this.importDatabase(config, args.backupFile);
      case "odoo_get_logs":
        return this.getLogs(config, args.lines || 50);
      case "odoo_get_project_dir":
        return this.getProjectDir(config, args.project);
      case "odoo_get_odoo_addon_dir":
        return this.getOdooAddonDir(config);
      case "odoo_get_enterprise_dir":
        return this.getEnterpriseDir(config);
      case "odoo_get_config_path":
        return this.getConfigPath(config);
      case "odoo_get_project_config_path":
        return this.getProjectConfigPath(config, args.project);
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }

  private executeCommand(config: OdooConfig, command: string): string {
    try {
      console.error(`[Executing] ${command}`);
      const result = execSync(command, {
        cwd: config.root,
        encoding: "utf-8",
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer
        timeout: 300000, // 5 minute timeout
      });
      console.error(`[Success] Command completed`);
      return result;
    } catch (error: any) {
      console.error(`[Command Error]`, error.message);
      // execSync throws if exit code is non-zero
      if (error.stdout) {
        return error.stdout;
      }
      if (error.stderr) {
        console.error(`[STDERR]`, error.stderr);
      }
      throw new Error(`Command failed: ${error.message}`);
    }
  }

  private async startOdoo(config: OdooConfig): Promise<any> {
    const output = this.executeCommand(config, "./manage_odoo.sh start");
    return {
      content: [
        {
          type: "text",
          text: `Odoo started:\n${output}`,
        },
      ],
    };
  }

  private async stopOdoo(config: OdooConfig): Promise<any> {
    const output = this.executeCommand(config, "./manage_odoo.sh stop");
    return {
      content: [
        {
          type: "text",
          text: `Odoo stopped:\n${output}`,
        },
      ],
    };
  }

  private async restartOdoo(config: OdooConfig): Promise<any> {
    const output = this.executeCommand(config, "./manage_odoo.sh restart");
    return {
      content: [
        {
          type: "text",
          text: `Odoo restarted:\n${output}`,
        },

      ],
    };
  }

  private async checkStatus(config: OdooConfig): Promise<any> {
    const output = this.executeCommand(config, "./manage_odoo.sh status");
    return {
      content: [
        {
          type: "text",
          text: output,
        },
      ],
    };
  }

  private async updateModules(
    config: OdooConfig,
    modules: string,
    errorOnly: boolean
  ): Promise<any> {
    const errorFlag = errorOnly ? " --error-only" : "";
    const output = this.executeCommand(
      config,
      `./manage_odoo.sh update ${modules}${errorFlag}`
    );
    return {
      content: [
        {
          type: "text",
          text: `Modules updated: ${modules}\n${output}`,
        },
      ],
    };
  }

  private async installModules(
    config: OdooConfig,
    modules: string,
    errorOnly: boolean
  ): Promise<any> {
    const errorFlag = errorOnly ? " --error-only" : "";
    const output = this.executeCommand(
      config,
      `./manage_odoo.sh install ${modules}${errorFlag}`
    );
    return {
      content: [
        {
          type: "text",
          text: `Modules installed: ${modules}\n${output}`,
        },
      ],
    };
  }

  private async updateFrontend(
    config: OdooConfig,
    modules: string,
    errorOnly: boolean
  ): Promise<any> {
    const errorFlag = errorOnly ? " --error-only" : "";
    const output = this.executeCommand(
      config,
      `./manage_odoo.sh frontend ${modules}${errorFlag}`
    );
    return {
      content: [
        {
          type: "text",
          text: `Frontend modules updated: ${modules}\n${output}`,
        },
      ],
    };
  }

  private async runTests(
    config: OdooConfig,
    modules?: string,
    testTags?: string,
    errorOnly?: boolean
  ): Promise<any> {
    let command = "./manage_odoo.sh test";
    
    if (modules) {
      command += ` ${modules}`;
    }
    
    if (testTags) {
      command += ` ${testTags}`;
    }
    
    if (errorOnly) {
      command += " --error-only";
    }
    
    const output = this.executeCommand(config, command);
    return {
      content: [
        {
          type: "text",
          text: `Test results:\n${output}`,
        },
      ],
    };
  }

  private async startShell(config: OdooConfig): Promise<any> {
    return {
      content: [
        {
          type: "text",
          text: `To start Odoo shell, run this command in your terminal:\ncd ${config.root} && ./manage_odoo.sh shell\n\nNote: This is an interactive command that requires direct terminal access.`,
        },
      ],
    };
  }

  private async getLogs(config: OdooConfig, lines: number): Promise<any> {
    const logFile = join(config.root, "odoo.log");
    
    if (!existsSync(logFile)) {
      return {
        content: [
          {
            type: "text",
            text: `Log file not found: ${logFile}`,
          },
        ],
      };
    }

    const output = this.executeCommand(config, `tail -n ${lines} odoo.log`);
    return {
      content: [
        {
          type: "text",
          text: `Last ${lines} lines of odoo.log:\n${output}`,
        },
      ],
    };
  }

  private async listDatabases(config: OdooConfig): Promise<any> {
    // Look for odoo*.conf files in the root directory
    try {
      const files = readdirSync(config.root);
      const confFiles = files.filter(f => f.startsWith("odoo") && f.endsWith(".conf"));
      
      // Read current database from odoo.conf
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
      confFiles.forEach(file => {
        const marker = file === "odoo.conf" ? " (active)" : "";
        output += `  - ${file}${marker}\n`;
      });

      return {
        content: [
          {
            type: "text",
            text: output,
          },
        ],
      };
    } catch (error: any) {
      throw new Error(`Failed to list databases: ${error.message}`);
    }
  }

  private async switchDatabase(
    config: OdooConfig,
    project: string
  ): Promise<any> {
    const targetConf = join(config.root, `odoo-${project}.conf`);
    const currentConf = join(config.root, "odoo.conf");

    if (!existsSync(targetConf)) {
      throw new Error(`Configuration file not found: odoo-${project}.conf`);
    }

    try {
      // Backup current config
      const backupConf = join(config.root, "odoo.conf.backup");
      if (existsSync(currentConf)) {
        this.executeCommand(config, `cp odoo.conf odoo.conf.backup`);
      }

      // Copy target config to odoo.conf
      this.executeCommand(config, `cp odoo-${project}.conf odoo.conf`);

      // Restart Odoo if it's running
      const statusOutput = this.executeCommand(config, "./manage_odoo.sh status");
      if (statusOutput.includes("running")) {
        this.executeCommand(config, "./manage_odoo.sh restart");
        return {
          content: [
            {
              type: "text",
              text: `Switched to database: ${project}\nOdoo has been restarted.`,
            },
          ],
        };
      } else {
        return {
          content: [
            {
              type: "text",
              text: `Switched to database: ${project}\nOdoo is not running. Start it with odoo_start.`,
            },
          ],
        };
      }
    } catch (error: any) {
      throw new Error(`Failed to switch database: ${error.message}`);
    }
  }

  private async importDatabase(
    config: OdooConfig,
    backupFile: string
  ): Promise<any> {
    if (!existsSync(backupFile)) {
      throw new Error(`Backup file not found: ${backupFile}`);
    }

    if (!backupFile.endsWith(".zip")) {
      throw new Error("Backup file must be a .zip file");
    }

    try {
      const output = this.executeCommand(
        config,
        `unzip -o "${backupFile}" -d /tmp/odoo_import_temp`
      );

      // Check if dump.sql exists
      const dumpFile = "/tmp/odoo_import_temp/dump.sql";
      if (!existsSync(dumpFile)) {
        throw new Error("Invalid backup: dump.sql not found in backup archive");
      }

      return {
        content: [
          {
            type: "text",
            text: `Database import requires manual steps:\n\n1. Backup extracted to: /tmp/odoo_import_temp\n2. Create/restore PostgreSQL database:\n   dropdb database_name\n   createdb database_name\n   psql database_name < /tmp/odoo_import_temp/dump.sql\n\n3. Restore filestore:\n   cp -r /tmp/odoo_import_temp/filestore/* ~/.local/share/Odoo/filestore/database_name/\n\n4. Update odoo.conf with database name\n5. Restart Odoo\n\nNote: Full automation of this process requires PostgreSQL credentials and is not yet implemented.`,
          },
        ],
      };
    } catch (error: any) {
      throw new Error(`Failed to import database: ${error.message}`);
    }
  }

  private async getProjectDir(
    config: OdooConfig,
    project: string
  ): Promise<any> {
    const projectPath = join(config.root, project);
    
    if (!existsSync(projectPath)) {
      return {
        content: [
          {
            type: "text",
            text: `Project directory not found: ${projectPath}`,
          },
        ],
        isError: true,
      };
    }

    // Check if it's a symlink and get the real path
    try {
      const stats = this.executeCommand(config, `ls -la ${project} | grep "^l"`);
      const realPath = this.executeCommand(config, `readlink -f ${project}`).trim();
      
      return {
        content: [
          {
            type: "text",
            text: `Project directory: ${projectPath}\nReal path: ${realPath}\n\nThis is your custom addons directory for the ${project} project.`,
          },
        ],
      };
    } catch (error) {
      // Not a symlink or error reading
      return {
        content: [
          {
            type: "text",
            text: `Project directory: ${projectPath}\n\nThis is your custom addons directory for the ${project} project.`,
          },
        ],
      };
    }
  }

  private async getOdooAddonDir(config: OdooConfig): Promise<any> {
    const addonPath = join(config.root, "odoo");
    
    if (!existsSync(addonPath)) {
      return {
        content: [
          {
            type: "text",
            text: `Odoo core addon directory not found: ${addonPath}`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text: `Odoo core addons directory: ${addonPath}\n\nThis contains the standard Odoo community modules.`,
        },
      ],
    };
  }

  private async getEnterpriseDir(config: OdooConfig): Promise<any> {
    const enterprisePath = join(config.root, "enterprise");
    
    if (!existsSync(enterprisePath)) {
      return {
        content: [
          {
            type: "text",
            text: `Enterprise directory not found: ${enterprisePath}`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text: `Odoo Enterprise addons directory: ${enterprisePath}\n\nThis contains the Odoo Enterprise modules.`,
        },
      ],
    };
  }

  private async getConfigPath(config: OdooConfig): Promise<any> {
    const configPath = join(config.root, "odoo.conf");
    
    if (!existsSync(configPath)) {
      return {
        content: [
          {
            type: "text",
            text: `Configuration file not found: ${configPath}`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text: `Active Odoo configuration: ${configPath}\n\nThis is the configuration file currently in use by Odoo.`,
        },
      ],
    };
  }

  private async getProjectConfigPath(
    config: OdooConfig,
    project: string
  ): Promise<any> {
    const configPath = join(config.root, `odoo-${project}.conf`);
    
    if (!existsSync(configPath)) {
      return {
        content: [
          {
            type: "text",
            text: `Project configuration file not found: ${configPath}\n\nExpected: odoo-${project}.conf`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text: `Project configuration: ${configPath}\n\nThis is the original configuration for the ${project} project.\nUse 'odoo_switch_database' to make this the active configuration.`,
        },
      ],
    };
  }

  async run() {
    try {
      const transport = new StdioServerTransport();
      await this.server.connect(transport);
      console.error("Odoo MCP Server running on stdio");
      console.error("Available versions:", Object.keys(this.configs).join(", "));
      console.error("Default version: odoo18");
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
