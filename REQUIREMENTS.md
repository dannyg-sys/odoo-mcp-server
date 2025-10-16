# Odoo MCP Server - Requirements

## Overview
Create an MCP (Model Context Protocol) server for managing Odoo 18 development environments. This server will wrap the existing `manage_odoo.sh` script functionality and provide additional database management capabilities.

## Project Location
- **Server Root**: `~/git/odoo-mcp-server/`
- **Odoo 18 Root**: `~/git/odoo18/`
- **Management Script**: `~/git/odoo18/manage_odoo.sh`
- **Documentation**: `~/git/odoo18/manage_odoo.md`

## Core Requirements

### 1. Multi-Version Support
- Support multiple Odoo versions (currently odoo18)
- Each version should have a configurable root path
- Example: `odoo18: ~/git/odoo18`
- Extensible for future versions (odoo17, odoo19, etc.)

### 2. Server Control Operations
Based on `manage_odoo.sh` commands:

#### Basic Server Operations
- **start**: Start Odoo server if not running
  - Uses: `./manage_odoo.sh start`
  - Runs in background with nohup
  - Saves PID to `odoo.pid`
  - Logs to `odoo.log`

- **stop**: Stop running Odoo server
  - Uses: `./manage_odoo.sh stop`
  - Kills process with `pkill -f "odoo/odoo-bin -c odoo.conf"`
  - Removes PID file

- **restart**: Restart Odoo server
  - Uses: `./manage_odoo.sh restart`
  - Combines stop + start

- **status**: Check if Odoo is running
  - Uses: `./manage_odoo.sh status`
  - Checks PID file and process status

### 3. Module Management Operations

#### Update Modules
- **update**: Update one or more modules
  - Command: `./manage_odoo.sh update MODULE[,...]`
  - Options: `--error-only` flag for error-only output
  - Examples:
    - Single: `update purchase_dual_unit`
    - Multiple: `update sale,purchase,account`

#### Install Modules
- **install**: Install new modules
  - Command: `./manage_odoo.sh install MODULE[,...]`
  - Options: `--error-only` flag
  - Examples:
    - Single: `install stock_account`
    - Multiple: `install hr,project,timesheet`

#### Frontend Updates
- **frontend**: Update frontend modules (JS/XML) and auto-restart
  - Command: `./manage_odoo.sh frontend MODULE[,...]`
  - Automatically restarts Odoo to reload assets
  - Options: `--error-only` flag
  - Examples:
    - Single: `frontend nell_thai_qr_pos`
    - Multiple: `frontend nell_thai_qr_pos,pos_restaurant`

### 4. Testing Operations

#### Run Tests
- **test**: Run module tests
  - Command: `./manage_odoo.sh test [MODULE[,...]] [TAGS]`
  - Options: `--error-only` flag
  - Test Tags Support:
    - `at_install`: Tests during installation
    - `post_install`: Tests after installation
    - `standard`: Standard functional tests
    - `nocopy`: Tests not run in copy mode
  - Examples:
    - All tests: `test`
    - Specific module: `test purchase_dual_unit`
    - Multiple modules: `test sale,purchase`
    - With tags: `test '' at_install`
    - Module + tags: `test purchase_dual_unit post_install`

### 5. Interactive Shell
- **shell**: Start interactive Odoo shell
  - Command: `./manage_odoo.sh shell`
  - Uses IPython interface
  - Available variables: `env`, `registry`, `cr`
  - Example usage: `env['res.users'].search([('login', '=', 'admin')])`

### 6. Database Management (NEW)

#### Switch Database
- **switch_database**: Switch between different database configurations
  - Parameters: `project` name (e.g., 'hhfbs', 'tora', 'nellika')
  - Should update `odoo.conf` to point to different database
  - May require server restart

#### List Databases
- **list_databases**: List available database configurations
  - Show all available project databases
  - Display current active database

#### Import Database
- **import_database**: Import Odoo database from backup
  - Parameters: `backupFile` (path to .zip file)
  - Standard Odoo backup format (.zip containing:
    - dump.sql (PostgreSQL dump)
    - filestore/ (attachment files)
    - manifest.json (metadata)
  - Steps:
    1. Extract backup file
    2. Create/restore PostgreSQL database
    3. Restore filestore
    4. Update odoo.conf if needed

### 7. Logging Operations
- **get_logs**: Retrieve Odoo logs
  - Get last N lines from `odoo.log`
  - Default: 50 lines
  - Useful for debugging

## Technical Specifications

### Technology Stack
- **Language**: TypeScript
- **Runtime**: Node.js
- **Framework**: MCP SDK (@modelcontextprotocol/sdk)
- **Build**: TypeScript compiler
- **Transport**: stdio (standard input/output)

### Configuration Structure
```typescript
interface OdooConfig {
  root: string;      // Root directory path
  name: string;      // Human-readable name
}
```

### Default Configurations
```typescript
const DEFAULT_CONFIGS: Record<string, OdooConfig> = {
  odoo18: {
    root: "~/git/odoo18",
    name: "Odoo 18"
  }
};
```

### Error Handling
- Validate Odoo version exists
- Check root directory exists
- Handle command execution errors
- Return clear error messages
- 10MB buffer for command output

### Command Execution
- Use `execSync` from child_process
- Execute in Odoo root directory
- Capture stdout and stderr
- Encoding: utf-8
- Max buffer: 10MB

## MCP Tool Definitions

All tools should follow this pattern:
1. Accept `version` parameter (default: "odoo18")
2. Accept tool-specific parameters
3. Return structured response with text content
4. Handle errors gracefully

### Tool List
1. `odoo_start` - Start server
2. `odoo_stop` - Stop server
3. `odoo_restart` - Restart server
4. `odoo_status` - Check status
5. `odoo_update_modules` - Update modules
6. `odoo_install_modules` - Install modules
7. `odoo_update_frontend` - Update frontend + restart
8. `odoo_run_tests` - Run tests
9. `odoo_shell` - Interactive shell
10. `odoo_switch_database` - Switch database
11. `odoo_list_databases` - List databases
12. `odoo_import_database` - Import database backup
13. `odoo_get_logs` - Get log entries

## User Experience Goals

### Problem Statement
AI assistants keep forgetting Odoo management commands, requiring repeated explanations of:
- How to start/stop Odoo
- How to update modules
- How to switch databases
- How to import databases

### Solution
Create a single "Manage ODOO" MCP server that:
- Centralizes all Odoo management operations
- Provides consistent interface across AI sessions
- Eliminates need to explain commands repeatedly
- Supports multiple Odoo versions from one server

## Future Enhancements
- Support for Odoo 17, 19, etc.
- Custom configuration file support
- Database backup operations
- Module scaffolding
- Log filtering and analysis
- Performance monitoring
- Multi-instance management
