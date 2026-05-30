# Odoo development base (`~/odoo`)

This directory is the **Odoo base**: the working tree that holds the Odoo sources,
every project's configuration, and the per-project custom-addon symlinks. All Odoo
management runs against this base.

> Managed by the tooling in `~/git/odoo-mcp-server` (engine + CLI + MCP + skill).
> Run `odoo help` for the command list.

## Layout

System dirs are prefixed with `_` so they stand out from the project addon
symlinks (which have no prefix):

```
~/odoo/
  _odoo18/         Odoo Community 18 source        (odoo-bin)
  _enterprise18/   Odoo Enterprise 18 addons
  _odoo19/         Odoo Community 19 source
  _enterprise19/   Odoo Enterprise 19 addons
  _venv18/         Python venv for 18
  _venv19/         Python venv for 19
  _data/           filestore + sessions
  _scripts/<project>/    ad-hoc helper scripts (test/seed/clean) — see below
  _concepts/<project>/   exploratory / new-concept scripts (knowledge base)
  odoo.conf        ACTIVE config (a copy of the selected odoo-<project>.conf)
  odoo-<project>.conf   one per project (hhfbs, nellika, verita, tora, …)
  <project>        symlink -> ~/git/<repo>   (a project's custom addons)
  odoo.log         server log     odoo.pid  running server PID
```

### Helper scripts (`_scripts/`) and concepts (`_concepts/`)
Ad-hoc scripts (test, seed, clean, fix-ups) go in `_scripts/<project>/`, never in
a project addon dir or the base root. `_concepts/<project>/` holds exploratory /
new-concept scripts (including one-off XML-RPC tools) kept as a knowledge base.
Each script starts with a short header comment of what it is for — max 3 lines,
each ≤80 chars.

### 18 vs 19 is per-project, not a separate tree
The active `odoo.conf` selects the Odoo version via its markers and addons_path:

```
; odoo_src = _odoo19        # which source tree (default: _odoo18)
; python_venv = _venv19     # which venv (default: _venv18)
addons_path = ./_odoo19/addons,./_enterprise19,./<project>
```

`manage_odoo.sh` reads `odoo_src` / `python_venv`; the addons_path picks 18 vs 19
sources. **Switching the project is what changes the running version** — there is
no separate version switch. Today only **verita** runs on 19; the rest run on 18.

## The `odoo` command (recommended)

`odoo` is the smart front door (it adds output filtering and path helpers). It is
the same code the Claude Code skill and the Claude Desktop MCP use.

```
odoo status                 # is Odoo running?
odoo start | stop | restart
odoo list                   # available projects + the active one
odoo switch <project>       # activate odoo-<project>.conf and restart (changes 18/19 too)
odoo new <name> [--version 18|19] [--enterprise] [--modules a,b,c]   # scaffold + switch to a new project
odoo update <modules>       # update module(s), restart — FILTERED output
odoo install <modules>      # install module(s)        — FILTERED output
odoo frontend <modules>     # update frontend + restart — FILTERED output
odoo test [modules]         # run tests; --tags <tags> to filter
odoo logs                   # tail odoo.log; --lines <n> for the full log
odoo shell                  # prints the interactive-shell command
odoo addons-dir             # active core addons dir (_odoo18/ or _odoo19/ -> tells the version)
odoo enterprise-dir         # active enterprise dir (_enterprise18/ or _enterprise19/)
odoo config-path | project-config <p> | project-dir <p>
```

Options: `--error-only` (suppress warnings on update/install/frontend/test),
`--tags <tags>`, `--lines <n>`, `--base <path>` (defaults to this base).

**Filtered output:** `update`/`install`/`frontend` collapse verbose logs to
`✓ … success`, `ℹ️ Warnings …`, or `⚠️ ERRORS FOUND …`. For the full log use
`odoo logs --lines 200` (everything is always in `odoo.log`).

## The `manage_odoo` command (raw engine)

`manage_odoo` is the underlying bash engine — same verbs, but **unfiltered** output.
It operates on `$ODOO_BASE` (default `~/odoo`). Use it when you want raw logs:

```
manage_odoo status
manage_odoo update <modules> [--error-only]
manage_odoo switch <project>        # alias for switch_config
ODOO_BASE=/some/other/base manage_odoo status
```

`odoo` is the engine wrapped with filtering; prefer `odoo` unless you need raw output.

## Driving Odoo from Claude

- **Claude Code:** the `odoo-manage` skill triggers on requests like "start odoo",
  "update module X", "switch to nellika", "run tests for sale". It calls the same
  CLI as `odoo`.
- **Claude Desktop:** the `odoo` MCP server exposes the same operations as tools
  (`odoo_start`, `odoo_update_modules`, `odoo_switch_database`, …). Configure it in
  `claude_desktop_config.json` pointing at `~/git/odoo-mcp-server/build/index.js`.

Both share one engine (`manage_odoo.sh`) and one wrapper (`core.ts`), so behavior is
identical across the terminal, Claude Code, and Claude Desktop.

## Reinstalling the tooling (e.g. on another machine)

```
git clone https://github.com/dannyg-sys/odoo-mcp-server.git ~/git/odoo-mcp-server
cd ~/git/odoo-mcp-server && npm install && npm run build && npm run setup
```
