# Odoo MCP Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.7-blue)](https://www.typescriptlang.org/)
[![MCP](https://img.shields.io/badge/MCP-1.0-green)](https://modelcontextprotocol.io/)

An MCP (Model Context Protocol) server for managing Odoo development environments with AI assistants.

## 🎯 Overview

This MCP server provides 19 tools to manage Odoo development environments, allowing AI assistants to:
- Control Odoo server (start, stop, restart, status)
- Manage modules (update, install, test)
- Switch between databases
- Navigate project directories
- View logs and configurations

Perfect for developers who want their AI assistants to remember and manage Odoo operations consistently across conversations.

## Features

- **Server Control**: Start, stop, restart, and check status of Odoo server
- **Module Management**: Update, install, and manage Odoo modules
- **Frontend Updates**: Update frontend modules with automatic server restart
- **Testing**: Run Odoo tests with optional filtering
- **Database Management**: Switch between databases, list available databases
- **Logging**: Retrieve Odoo log entries

## Installation

### 1. Install Dependencies

```bash
cd ~/git/odoo-mcp-server
npm install
```

### 2. Configure Claude Desktop

Add to your Claude Desktop config file (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "odoo": {
      "command": "node",
      "args": ["/Users/dgoo2308/git/odoo-mcp-server/build/index.js"]
    }
  }
}
```

### 3. Restart Claude Desktop

The Odoo management tools will now be available in Claude.

## Available Tools

### Server Control
- `odoo_start` - Start Odoo server
- `odoo_stop` - Stop Odoo server  
- `odoo_restart` - Restart Odoo server
- `odoo_status` - Check server status

### Module Management
- `odoo_update_modules` - Update one or more modules
- `odoo_install_modules` - Install new modules
- `odoo_update_frontend` - Update frontend modules (auto-restarts)

### Testing
- `odoo_run_tests` - Run tests with optional module and tag filters

### Database Management
- `odoo_switch_database` - Switch to a different database configuration
- `odoo_list_databases` - List available database configurations
- `odoo_import_database` - Import database from backup (partial support)

### Other
- `odoo_shell` - Instructions for starting interactive shell
- `odoo_get_logs` - Retrieve last N lines from logs

### Directory & Config Helpers
- `odoo_get_project_dir` - Get path to project's custom addon directory
- `odoo_get_odoo_addon_dir` - Get path to Odoo core addons
- `odoo_get_enterprise_dir` - Get path to Enterprise addons
- `odoo_get_config_path` - Get path to active odoo.conf
- `odoo_get_project_config_path` - Get path to project-specific config

## Usage Examples

```
"Start Odoo"
"Update the purchase_dual_unit module"
"Install stock_account and hr modules"
"Run tests for the sale module"
"Switch to the nellika database"
"Show me the last 100 log lines"
"Where is the project directory for hhfbs?"
"What's the path to the Odoo core addons?"
"Show me the enterprise directory"
```

## Configuration

### Adding New Odoo Versions

Edit `src/index.ts` and add to `DEFAULT_CONFIGS`:

```typescript
const DEFAULT_CONFIGS: Record<string, OdooConfig> = {
  odoo18: {
    root: join(os.homedir(), "git", "odoo18"),
    name: "Odoo 18"
  },
  odoo17: {
    root: join(os.homedir(), "git", "odoo17"),
    name: "Odoo 17"
  }
};
```

Then rebuild:

```bash
npm run build
```

## Requirements

- Node.js 16+
- Odoo development environment with `manage_odoo.sh` script
- Claude Desktop

## Development

```bash
# Build
npm run build

# Watch mode (auto-rebuild)
npm run watch
```

## Troubleshooting

### Server not found in Claude

1. Check Claude Desktop config file path
2. Ensure build directory exists: `ls ~/git/odoo-mcp-server/build/`
3. Restart Claude Desktop completely

### Commands failing

1. Check Odoo root path exists: `ls ~/git/odoo18`
2. Verify `manage_odoo.sh` exists and is executable
3. Check logs with `odoo_get_logs`

## License

MIT
