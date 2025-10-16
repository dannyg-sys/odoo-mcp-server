# Update: Added Directory & Config Helper Tools

**Date**: October 16, 2025

## What Was Added

5 new tools to help AI maintain context about the Odoo project structure:

### New Tools

1. **`odoo_get_project_dir`** - Get project's custom addon directory
   - Path: `~/git/odoo18/<project>`
   - Usually a symlink to `~/git/<project>`
   - Shows both symlink and real path
   - Example: "Where is the hhfbs project directory?"

2. **`odoo_get_odoo_addon_dir`** - Get Odoo core addons path
   - Path: `~/git/odoo18/odoo`
   - Contains standard community modules
   - Example: "What's the path to Odoo core addons?"

3. **`odoo_get_enterprise_dir`** - Get Enterprise addons path
   - Path: `~/git/odoo18/enterprise`
   - Contains Odoo Enterprise modules
   - Example: "Show me the enterprise directory"

4. **`odoo_get_config_path`** - Get active config file path
   - Path: `~/git/odoo18/odoo.conf`
   - Currently active configuration
   - Example: "Where is the active Odoo config?"

5. **`odoo_get_project_config_path`** - Get project-specific config
   - Path: `~/git/odoo18/odoo-<project>.conf`
   - Original config file before switching
   - Example: "Where is the nellika config file?"

## Why These Are Useful

**Problem**: AI loses context between conversations about:
- Where to find modules (core vs enterprise vs custom)
- Which directory to work in
- Project structure and paths

**Solution**: AI can now ask itself:
- "Where should I look for this module?"
- "What's the custom addon directory?"
- "Where is the project config?"

## Usage Patterns

### Finding Modules
```
AI: "Let me check the enterprise directory first"
   -> calls odoo_get_enterprise_dir
   -> gets: ~/git/odoo18/enterprise
   -> searches there for the module
```

### Working on Custom Addons
```
AI: "I need to work on the hhfbs project"
   -> calls odoo_get_project_dir with project="hhfbs"
   -> gets: ~/git/odoo18/hhfbs -> ~/git/hhfbs
   -> works in the real directory
```

### Configuration Management
```
AI: "Let me check what config is active"
   -> calls odoo_get_config_path
   -> reads the active odoo.conf
```

## Build Status

✅ Successfully compiled
- Source: 938 lines (src/index.ts)
- Output: 820 lines (build/index.js)
- All 18 tools working

## Total Tools Now: 18

### Server Control (4)
- start, stop, restart, status

### Module Management (3)
- update_modules, install_modules, update_frontend

### Testing (1)
- run_tests

### Database Management (3)
- switch_database, list_databases, import_database

### Logging (1)
- get_logs

### Interactive (1)
- shell

### Directory & Config Helpers (5) ⭐ NEW
- get_project_dir
- get_odoo_addon_dir
- get_enterprise_dir
- get_config_path
- get_project_config_path

## Next Steps

No action needed - just restart Claude Desktop if it's already running!

The new tools will automatically be available.
