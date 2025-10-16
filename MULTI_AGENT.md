# Multi-Agent Usage - Best Practices

## Current Behavior (No Locking)

The Odoo MCP server currently has **no coordination between agents**. This means:

### ⚠️ Unsafe Operations (Avoid Concurrent Use)

**DO NOT run these simultaneously from multiple agents:**

1. **Server Control** (can conflict):
   - `odoo_start`
   - `odoo_stop`
   - `odoo_restart`

2. **Module Operations** (Odoo only allows one at a time):
   - `odoo_update_modules`
   - `odoo_update_module`
   - `odoo_install_modules`
   - `odoo_update_frontend`
   - `odoo_run_tests`

3. **Database Switching** (file conflicts):
   - `odoo_switch_database`

### ✅ Safe Operations (Can Run Concurrently)

**These are safe for multiple agents:**

- `odoo_status` - Read-only check
- `odoo_get_logs` - Read log files
- `odoo_list_databases` - List configs
- `odoo_get_project_dir` - Get paths
- `odoo_get_odoo_addon_dir` - Get paths
- `odoo_get_enterprise_dir` - Get paths
- `odoo_get_config_path` - Get paths
- `odoo_get_project_config_path` - Get paths

All the `get_*` tools are read-only and completely safe.

## Recommended Workflow

### Single Agent at a Time
**Best approach**: Only use one AI agent for Odoo management operations at a time.

```
✅ Good:
- Agent A manages Odoo
- Agent B does other tasks (code review, documentation, etc.)

❌ Bad:
- Agent A: "Restart Odoo"
- Agent B: "Update module X" (at same time)
```

### Coordinate Between Agents

If you must use multiple agents:

1. **Check status first**:
   ```
   Agent 1: "Check if Odoo is running"
   Agent 2: "Check if Odoo is running"
   ```

2. **Wait for completion**:
   ```
   Agent 1: "Update module X"
   (wait for completion)
   Agent 2: "Update module Y"
   ```

3. **Use different Odoo versions**:
   ```
   Agent 1: Works on odoo18
   Agent 2: Works on odoo17
   ✅ No conflict - different directories
   ```

## Error Messages You Might See

### If Two Agents Conflict:

**Starting Odoo:**
```
Odoo is already running with PID: 12345
```
This is actually safe - the second agent just gets told Odoo is running.

**Updating Modules:**
```
Error: Could not acquire database lock
```
Odoo itself prevents concurrent updates - second agent will fail gracefully.

**Database Switching:**
```
Error: Failed to switch database
```
File operations might conflict, causing unpredictable results.

## Technical Details

### How MCP Works

```
┌─────────────┐         ┌──────────────┐
│  AI Agent 1 │ ───────>│ MCP Server 1 │
└─────────────┘         └──────────────┘
                               │
                               ▼
                        ~/git/odoo18/
                        (shared files)
                               ▲
                               │
┌─────────────┐         ┌──────────────┐
│  AI Agent 2 │ ───────>│ MCP Server 2 │
└─────────────┘         └──────────────┘
```

**Problem**: Both servers write to same files:
- `odoo.pid` - Process ID
- `odoo.conf` - Configuration
- `odoo.log` - Log file (this is OK, append-only)

### What Odoo Does

Odoo has **some** built-in protections:
- ✅ Database locks prevent concurrent updates
- ✅ Only one server can bind to port 8069
- ❌ No protection for config file changes
- ❌ No protection for PID file

## Future Enhancement: Add Locking

See `LOCKING_EXAMPLE.md` for how to add file-based locks to prevent conflicts.

**With locking, second agent would get:**
```
Another agent is currently [starting/updating/switching] Odoo. 
Please wait and try again.
```

## Quick Decision Guide

**Question**: Can I run this operation from multiple agents?

1. Is it a `get_*` or `odoo_status` command?
   - ✅ YES, safe to run concurrently

2. Does it modify Odoo or its configuration?
   - ❌ NO, use only one agent

3. Are the agents working on different Odoo versions?
   - ✅ YES, safe (completely separate directories)

4. Can I check status first?
   - ✅ YES, check with `odoo_status` before making changes

## Summary

**Current Implementation**: No locking, be careful with concurrent use

**Safe Pattern**: 
- Use one agent for Odoo operations
- Other agents can read status/logs
- Different versions = no problem

**Future**: Can add file-based locking if needed

**Recommendation**: Since you're likely the only user, and AI agents typically work sequentially in conversations, this is usually not a problem in practice!
