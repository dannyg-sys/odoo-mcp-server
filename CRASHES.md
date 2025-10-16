# MCP Server Goes Offline - Troubleshooting Guide

## Symptoms
- "MCP server ODOO is offline" error
- Server works initially but crashes later
- Similar to Desktop Commander failures

## Common Causes

### 1. Command Timeout or Hang
**Problem**: Long-running commands (module updates, tests) may timeout or hang

**Solution**: Added 5-minute timeout to all commands

### 2. Uncaught Exceptions
**Problem**: Errors in command execution crash the entire server

**Solution**: Added comprehensive error handling:
- `uncaughtException` handler
- `unhandledRejection` handler  
- Better error logging

### 3. Resource Exhaustion
**Problem**: Large command outputs overflow buffers

**Solution**: Set 10MB buffer limit for command outputs

### 4. Process Killed by System
**Problem**: System or parent process kills the MCP server

**Solution**: Added auto-restart wrapper script

## Quick Fixes

### Fix 1: Use the Auto-Restart Wrapper

Update your MCP config to use the restart wrapper:

```json
{
  "manage_odoo": {
    "command": "/Users/dgoo2308/git/odoo-mcp-server/run-with-restart.sh",
    "env": {},
    "working_directory": null
  }
}
```

This will automatically restart the server if it crashes.

### Fix 2: Check the Logs

View real-time logs:
```bash
tail -f /tmp/odoo-mcp-server.log
```

The logs will show:
- When server starts
- What commands are executed
- Any errors that occur
- Restart attempts

### Fix 3: Test the Server Manually

```bash
cd /Users/dgoo2308/git/odoo-mcp-server
node build/index.js
```

Should output:
```
Odoo MCP Server running on stdio
Available versions: odoo18
Default version: odoo18
```

If it crashes, you'll see the error.

### Fix 4: Reduce Command Timeout

If operations take too long, edit `src/index.ts`:

```typescript
timeout: 300000, // 5 minutes - reduce if needed
```

### Fix 5: Check Odoo Directory

Make sure the Odoo directory exists and is accessible:

```bash
ls -la ~/git/odoo18/
# Should show: odoo/, enterprise/, manage_odoo.sh, etc.
```

## Debugging Steps

### Step 1: Enable Detailed Logging

The server now logs to stderr. View logs with:

```bash
# If using wrapper
tail -f /tmp/odoo-mcp-server.log

# If using direct node command, check Warp's MCP logs
# (location depends on Warp configuration)
```

### Step 2: Identify the Crashing Command

Logs will show:
```
[Executing] ./manage_odoo.sh restart
[Success] Command completed
```

Or if it crashes:
```
[Executing] ./manage_odoo.sh update module_name
[Command Error] ...error message...
```

### Step 3: Test the Failing Command

Run it manually:
```bash
cd ~/git/odoo18
./manage_odoo.sh <the-command-that-failed>
```

### Step 4: Check System Resources

```bash
# Check if system is out of memory
top

# Check disk space
df -h

# Check if Odoo process is stuck
ps aux | grep odoo
```

## Specific Error Patterns

### Error: "Command failed: timeout"
**Cause**: Command took longer than 5 minutes  
**Fix**: Increase timeout or break into smaller operations

### Error: "ENOENT: no such file"
**Cause**: Odoo directory or manage_odoo.sh not found  
**Fix**: Check paths in config, verify ~/git/odoo18 exists

### Error: "MaxBuffer exceeded"
**Cause**: Command output > 10MB  
**Fix**: Use `errorOnly: true` flag to reduce output

### Error: "spawn ENOMEM"
**Cause**: Out of memory  
**Fix**: Close other applications, increase system memory

## Prevention

### Best Practices

1. **Use error-only flag** for routine operations:
   ```
   "Update module with error-only output"
   ```

2. **Check status before operations**:
   ```
   "Check Odoo status" (always works, helps keep server alive)
   ```

3. **Avoid very long operations**:
   - Instead of updating 10 modules at once
   - Update them in smaller batches

4. **Use read-only operations frequently**:
   - `odoo_status`
   - `odoo_get_logs`
   - `odoo_list_databases`
   
   These are lightweight and keep the connection healthy.

## Configuration Comparison

### Standard Config (May Crash)
```json
{
  "manage_odoo": {
    "command": "node",
    "args": ["/Users/dgoo2308/git/odoo-mcp-server/build/index.js"]
  }
}
```

### Robust Config (Auto-Restart)
```json
{
  "manage_odoo": {
    "command": "/Users/dgoo2308/git/odoo-mcp-server/run-with-restart.sh"
  }
}
```

The wrapper script will:
- Restart server automatically if it crashes
- Log all restarts to /tmp/odoo-mcp-server.log
- Give up after 5 crashes in 60 seconds (prevents infinite loops)
- Exit cleanly on SIGINT/SIGTERM

## Emergency Recovery

If the server keeps crashing:

1. **Restart Warp completely**
2. **Check for zombie Odoo processes**:
   ```bash
   pkill -f "odoo-bin"
   ```

3. **Clean up lock files**:
   ```bash
   cd ~/git/odoo18
   rm -f odoo.pid
   ```

4. **Rebuild the MCP server**:
   ```bash
   cd ~/git/odoo-mcp-server
   npm run build
   ```

5. **Test manually first**:
   ```bash
   node build/index.js
   # Try some commands
   ```

## Getting Help

If server still crashes, check:

1. **Server logs**: `/tmp/odoo-mcp-server.log`
2. **Odoo logs**: `~/git/odoo18/odoo.log`
3. **Warp logs**: Check Warp's console for MCP-related errors
4. **System logs**: Console.app → search for "odoo-mcp-server"

Include these when asking for help!

## What Changed

The updated server now has:

✅ 5-minute command timeout  
✅ Uncaught exception handlers  
✅ Better error logging  
✅ Auto-restart wrapper script  
✅ Process signal handlers (SIGTERM, SIGINT)  
✅ Detailed command execution logs  

This should make it much more stable!
