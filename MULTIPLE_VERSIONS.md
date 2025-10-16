# Setting Up Multiple Odoo Versions

## Overview

You can configure Claude Desktop to work with multiple Odoo versions simultaneously (Odoo 17, 18, 19, 20, etc.) by adding multiple MCP server configurations.

## Method 1: Single Server, Multiple Versions (Recommended)

### Step 1: Update src/index.ts

Edit the `DEFAULT_CONFIGS` in `src/index.ts`:

```typescript
const DEFAULT_CONFIGS: Record<string, OdooConfig> = {
  odoo17: {
    root: join(os.homedir(), "git", "odoo17"),
    name: "Odoo 17"
  },
  odoo18: {
    root: join(os.homedir(), "git", "odoo18"),
    name: "Odoo 18"
  },
  odoo19: {
    root: join(os.homedir(), "git", "odoo19"),
    name: "Odoo 19"
  }
};
```

### Step 2: Rebuild

```bash
cd ~/git/odoo-mcp-server
npm run build
```

### Step 3: Configure Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

### Step 4: Use with Version Parameter

All tools accept a `version` parameter:

```
"Start Odoo 18" -> Uses default (odoo18)
"Start Odoo 17" -> Specify: odoo_start with version="odoo17"
"Update module in Odoo 19" -> Specify version="odoo19"
```

## Method 2: Separate Servers Per Version

If you prefer dedicated servers for each version:

### Setup

1. **Create multiple server directories**:
```bash
cp -r ~/git/odoo-mcp-server ~/git/odoo17-mcp-server
cp -r ~/git/odoo-mcp-server ~/git/odoo18-mcp-server
cp -r ~/git/odoo-mcp-server ~/git/odoo19-mcp-server
```

2. **Edit each server's DEFAULT_CONFIGS** to use only one version

3. **Configure Claude Desktop**:

```json
{
  "mcpServers": {
    "odoo17": {
      "command": "node",
      "args": ["/Users/dgoo2308/git/odoo17-mcp-server/build/index.js"]
    },
    "odoo18": {
      "command": "node",
      "args": ["/Users/dgoo2308/git/odoo18-mcp-server/build/index.js"]
    },
    "odoo19": {
      "command": "node",
      "args": ["/Users/dgoo2308/git/odoo19-mcp-server/build/index.js"]
    }
  }
}
```

## Recommended Approach

**Use Method 1** (Single Server) because:
- ✅ Easier to maintain (one codebase)
- ✅ Simpler configuration
- ✅ Less disk space
- ✅ Easier to update

**Use Method 2** (Separate Servers) only if:
- You need different tool sets per version
- You want complete isolation
- You have version-specific customizations

## Directory Structure Requirements

For each Odoo version, ensure this structure exists:

```
~/git/odoo18/
├── odoo/              # Core addons
├── enterprise/        # Enterprise addons
├── <project>/         # Custom project addons (symlinks)
├── odoo.conf          # Active config
├── odoo-<project>.conf # Project configs
├── manage_odoo.sh     # Management script
└── venv/              # Python virtual environment
```

## Example: Adding Odoo 19

### 1. Update Code
```typescript
// In src/index.ts, add to DEFAULT_CONFIGS:
odoo19: {
  root: join(os.homedir(), "git", "odoo19"),
  name: "Odoo 19"
}
```

### 2. Rebuild
```bash
npm run build
```

### 3. Restart Claude Desktop

### 4. Test
```
"List databases in Odoo 19"
"Start Odoo 19"
"Get the project directory for hhfbs in Odoo 19"
```

## Current Configuration

By default, the server is configured for:
- ✅ Odoo 18 at `~/git/odoo18`

To add more versions, follow the steps above!

## Notes

- All tools support the `version` parameter
- Default version is "odoo18" if not specified
- The server validates that the root directory exists
- The `manage_odoo.sh` script must exist in each version's root
