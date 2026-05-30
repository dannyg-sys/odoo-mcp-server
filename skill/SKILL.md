---
name: odoo-manage
description: Manage the local Odoo development environment under ~/git/odoo18 — start/stop/restart the server, update/install modules, run tests, switch between project databases (hhfbs, nellika, verita, tora, plasma, …), view logs, and locate addon/config dirs. Use when the user asks to start/stop/restart Odoo, update or install an Odoo module, run Odoo tests, switch the Odoo project or database, or check Odoo status/logs.
tools:
  - Bash(node:*)
---

# Odoo dev environment management

This skill drives the local Odoo development environment through a small CLI,
`odoo-cli` (`__ODOO_CLI__`). The CLI shares its implementation with the `odoo`
MCP server (same `core.ts`), including the smart log filtering — so you get the
same concise, error-focused output without the MCP server needing to be
connected.

> This is the Claude Code counterpart to the `odoo` MCP server (which is kept
> for Claude Desktop). Prefer this skill in Claude Code; the `odoo` MCP can be
> left disabled here to keep the context lean.

## Layout you are working with

- **Base (fixed):** `~/git/odoo18` — holds `manage_odoo.sh`, the active
  `odoo.conf`, and one `odoo-<project>.conf` per project.
- **Sources live inside the base:** `odoo/` (CE 18), `enterprise/` (EE 18),
  `odoo19/` (CE 19), `enterprise19/` (EE 19), plus `venv/` and `venv19/`.
- **18 vs 19 is per-project, not a separate tree.** The active `odoo.conf`
  selects it via the `; odoo_src = …` / `; python_venv = …` markers and its
  `addons_path`. Switching project (below) is what changes the running version.
  Today only **verita** runs on 19; the rest run on 18.

So "switch project" = swap which `odoo-<project>.conf` is active. There is no
version flag to set — picking the project picks the version.

## How to run it

Call the CLI with Bash. It prints a concise result to stdout; diagnostic
`[Executing]`/`[Success]` lines go to stderr.

```bash
node __ODOO_CLI__ <command> [args] [options]
```

If `__ODOO_CLI__` is missing (fresh checkout), build it first:
`cd __REPO_DIR__ && npm install && npm run build`.

## Commands

| Command | What it does |
|---|---|
| `status` | Is Odoo running? |
| `start` / `stop` / `restart` | Server control |
| `list` | List available project configs + the active one |
| `switch <project>` | Activate `odoo-<project>.conf` and restart (changes 18/19 too) |
| `update <modules>` | Update module(s) (comma-separated) and restart — **filtered output** |
| `install <modules>` | Install module(s) — **filtered output** |
| `frontend <modules>` | Update frontend module(s) and restart — **filtered output** |
| `test [modules]` | Run tests (all, or for given modules); `--tags <tags>` to filter |
| `logs` | Tail of `odoo.log`; `--lines <n>` (default 50) for the unfiltered log |
| `shell` | Prints the command to open an interactive Odoo shell (interactive — not run here) |
| `config-path` | Active `odoo.conf` path |
| `project-config <project>` | Path to a project's `odoo-<project>.conf` |
| `project-dir <project>` | A project's custom addons directory |
| `addons-dir` | Active Odoo core addons dir (resolves to odoo/ or odoo19/) |
| `enterprise-dir` | Active Enterprise addons dir (enterprise/ or enterprise19/) |

Options: `--error-only` (suppress warnings on update/install/frontend/test),
`--tags <tags>`, `--lines <n>`, `--base <version>` (default `odoo18`).

## Output filtering

`update`, `install`, and `frontend` collapse hundreds of verbose log lines into:
- `✓ Operation completed successfully …` when clean,
- `ℹ️ Warnings found …` with just the warning lines, or
- `⚠️ ERRORS FOUND …` with the error block + traceback.

When you need the full picture (e.g. to debug something filtering hid), use
`logs --lines 200` — the complete output is always in `odoo.log`.

## Typical flows

- **"Update module X"** → `node __ODOO_CLI__ update X`
  Read the filtered result; if it shows errors, pull `logs` for context.
- **"Switch to the nellika project"** → `switch nellika`, then `status`.
- **"Run the tests for sale"** → `test sale` (add `--error-only` for just failures).
- **"Which Odoo version is active?"** → `addons-dir` (odoo19/ ⇒ CE 19).

## Examples

```bash
node __ODOO_CLI__ status
node __ODOO_CLI__ switch verita
node __ODOO_CLI__ update nell_thai_qr --error-only
node __ODOO_CLI__ test purchase_dual_unit
node __ODOO_CLI__ logs --lines 200
```
