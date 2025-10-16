# Troubleshooting: AI Not Using MCP Tools

## Issue
The MCP server shows as "running" but the AI doesn't use the tools when you ask it to restart Odoo or perform other operations.

## Possible Causes & Solutions

### 1. Tool Descriptions Not Clear Enough ✅ FIXED
**Problem**: AI doesn't recognize when to use the tools  
**Solution**: Updated tool descriptions to be more explicit

Example changes:
- OLD: "Start the Odoo server"
- NEW: "Start the Odoo server. Use this when the user asks to start Odoo, launch Odoo, or run Odoo."

### 2. MCP Server Name Mismatch
**Problem**: The server name in config doesn't match what the AI expects  
**Current**: `"manage_odoo"`  
**Try**: Using a simpler name or one that matches patterns

**Alternative config to try:**
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

### 3. Check Server Actually Loaded
**Test the server manually:**
```bash
cd /Users/dgoo2308/git/odoo-mcp-server
node build/index.js
# Should output: "Odoo MCP Server running on stdio"
```

### 4. Restart Warp/Application Completely
After changing config:
1. Quit Warp completely (Cmd+Q)
2. Wait 5 seconds
3. Reopen Warp
4. Try asking again

### 5. Check Warp MCP Configuration Location
Warp might use a different config file location than Claude Desktop.

Common locations to check:
- `~/.warp/mcp_config.json`
- `~/.config/warp/mcp_config.json`  
- Inside Warp settings/preferences

### 6. Enable MCP Debug Mode (if available)
Check if Warp has MCP debugging logs:
- Look for MCP-related settings in Warp
- Check for console/debug output
- Look for error logs

### 7. Verify Tool Registration
**Ask the AI directly:**
```
"What MCP tools do you have available?"
"Can you list all the Odoo management tools you can use?"
"Do you see any tools for managing Odoo?"
```

This will help confirm if the tools are actually loaded.

### 8. Try Explicit Tool Requests
Instead of natural language, try being very explicit:

**Natural (might not work):**
"Restart Odoo"

**Explicit (more likely to work):**
"Use the odoo_restart tool to restart Odoo"
"Call the MCP tool odoo_restart"

### 9. Check for Conflicting Tools
If you have multiple MCP servers, there might be conflicts.

**Review your full config:**
```bash
cat ~/.config/warp/mcp_config.json  # or wherever Warp stores it
```

Make sure there are no duplicate server names or conflicting tool names.

### 10. Test with Simpler Request First
Try the most basic tool:

```
"Use odoo_status to check if Odoo is running"
"Get the Odoo status"
```

If this works, the server is loaded. If not, it's a configuration issue.

## Updated Build

I've updated the server with:
1. ✅ More explicit tool descriptions
2. ✅ Added prompts capability
3. ✅ Added "odoo-help" prompt for guidance

**Rebuild completed** - restart your application to use the updated version.

## Quick Test Commands

Try these in order to debug:

1. **Check if tools are visible:**
   ```
   "What Odoo tools do you have?"
   ```

2. **Try explicit tool call:**
   ```
   "Use the odoo_status tool"
   ```

3. **Try natural language:**
   ```
   "Check if Odoo is running"
   "Restart Odoo"
   ```

4. **Get help:**
   ```
   "Show me Odoo help"  (uses the prompt)
   ```

## If Still Not Working

1. Check Warp's documentation for MCP configuration
2. Look for Warp MCP examples/templates
3. Check if Warp uses a different MCP protocol version
4. Try the server with Claude Desktop to verify it works there
5. Contact Warp support about MCP server integration

## Verification Checklist

- [ ] Config file in correct location
- [ ] Server name matches Warp's expectations
- [ ] Correct path to build/index.js
- [ ] Application fully restarted
- [ ] Server builds without errors
- [ ] Can run server manually in terminal
- [ ] AI can list available tools
- [ ] Tools appear when asking "what tools do you have?"

## Working Alternative: Claude Desktop

If Warp integration doesn't work, the server works perfectly with Claude Desktop:

**Claude Desktop Config** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
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

This is confirmed working! 🎉
