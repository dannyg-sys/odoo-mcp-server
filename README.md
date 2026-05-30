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

## Architecture & the two surfaces

The management logic lives once, in `src/core.ts`, and is reached through two
thin entry points plus a Claude Code skill:

```
src/core.ts    All Odoo logic + smart output filtering (single source of truth)
src/index.ts   MCP server  → for Claude Desktop        (build/index.js)
src/cli.ts     odoo-cli    → for Claude Code / terminal (build/cli.js)
```

Skills and MCP reach your machine through different doors, so each Claude
surface uses the entry point that fits it:

| Surface | How it reaches local Odoo | What it uses |
|---|---|---|
| **Claude Desktop** | a local MCP process it launches | the **MCP server** (`build/index.js`) |
| **Claude Code** | host shell access | the **`odoo-manage` skill** → `odoo-cli` |

Why the split: a Claude Desktop skill runs sandboxed and cannot execute the
local CLI, so Desktop needs the MCP (a real local process) to touch your Odoo
install. Claude Code has host shell access, so a skill calling `odoo-cli` is the
lighter option there — the 19 MCP tool schemas don't have to sit in context.
Both paths run the same `core.ts`, including the identical output filtering.

The Claude Code skill lives at `~/.claude/skills/odoo-manage/SKILL.md` (it calls
`node ~/git/odoo-mcp-server/build/cli.js`). The orientation that Desktop needs is
carried by the MCP itself — the `odoo-help` prompt and the tool descriptions —
so no separate Desktop skill is required.

### Environment layout this manages

- **Base (fixed):** `~/git/odoo18` — holds `manage_odoo.sh`, the active
  `odoo.conf`, and one `odoo-<project>.conf` per project.
- **Sources live inside the base:** `odoo/` (CE 18), `enterprise/` (EE 18),
  `odoo19/` (CE 19), `enterprise19/` (EE 19), plus `venv/` and `venv19/`.
- **18 vs 19 is per-project, not a separate tree.** The active `odoo.conf`
  selects it via its `; odoo_src` / `; python_venv` markers and `addons_path`.
  Switching project (`odoo_switch_database` / `odoo-cli switch`) is what changes
  the running version — there is no version flag to set.

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

## CLI (Claude Code / terminal)

Build produces `build/cli.js` (exposed as the `odoo-cli` bin). The `odoo-manage`
Claude Code skill calls it, and you can run it directly:

```bash
node ~/git/odoo-mcp-server/build/cli.js <command> [args] [options]

# examples
node ~/git/odoo-mcp-server/build/cli.js status
node ~/git/odoo-mcp-server/build/cli.js list
node ~/git/odoo-mcp-server/build/cli.js switch verita
node ~/git/odoo-mcp-server/build/cli.js update nell_thai_qr --error-only
node ~/git/odoo-mcp-server/build/cli.js test purchase_dual_unit
node ~/git/odoo-mcp-server/build/cli.js logs --lines 200
```

Run `odoo-cli help` for the full command list. Result text goes to stdout;
`[Executing]`/`[Success]` diagnostics go to stderr. Options: `--error-only`,
`--tags <tags>`, `--lines <n>`, `--base <version>` (default `odoo18`).

## Install the Claude Code skill

The `odoo-manage` skill (source in `skill/SKILL.md`) lets Claude Code drive the
CLI. Install it into `~/.claude/skills` with:

```bash
cd ~/git/odoo-mcp-server
npm run install-skill        # or: ./install-skill.sh
```

The installer builds `build/cli.js` if needed and renders the skill with the
absolute path of *this* checkout, so it works no matter where the repo is
cloned. Re-run with `--force` to overwrite an existing install
(`./install-skill.sh --force`). Set `CLAUDE_SKILLS_DIR` to install somewhere
other than `~/.claude/skills`. Start a new Claude Code session to pick it up.

To set this up on another computer:

```bash
git clone https://github.com/dannyg-sys/odoo-mcp-server.git ~/git/odoo-mcp-server
cd ~/git/odoo-mcp-server
npm install && npm run build
npm run install-skill
```

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
- `odoo_switch_database` - Activate a project's config and restart (also changes the running 18/19 version)
- `odoo_list_databases` - List available project configurations and the active one
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

### Choosing the Odoo version

You normally don't. The Odoo version (18 vs 19) is selected per project by the
active `odoo.conf` — switch project with `odoo_switch_database` (or
`odoo-cli switch <project>`) and the version follows. See
[Environment layout](#environment-layout-this-manages).

### Using a different base directory

Both entry points default to the `~/git/odoo18` base. To target a different base
under `~/git`, pass a version name: the MCP tools accept a `version` argument and
the CLI accepts `--base <version>`, each resolving to `~/git/<version>`. The base
must contain a `manage_odoo.sh` script or resolution fails with a clear error.

```bash
node ~/git/odoo-mcp-server/build/cli.js status --base odoo18
```

After changing source, rebuild:

```bash
npm run build
```

## Requirements

- Node.js 16+
- Odoo development environment with `manage_odoo.sh` script
- Claude Desktop (MCP) and/or Claude Code (skill + CLI)

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
