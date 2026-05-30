# Odoo development base

This directory (`~/odoo`) is the local **Odoo development base**: one place that
holds the Odoo source trees, every project's configuration, and each project's
custom-addon symlink. You manage all of it with the `odoo` command.

> Looking for the rules Claude follows in this repo? See `CLAUDE.md`. This README
> is the human-facing version of the same information.

## Requirements & first-time setup

You need:

- **git**, **Python 3.10+**, and **PostgreSQL** (running, with a role matching the
  configs' `db_user` — `odoo` by default).
- **GitHub access to the private `odoo/enterprise` repository.** The Enterprise
  sources (`_enterprise18` / `_enterprise19`) are cloned from `odoo/enterprise`,
  which is private — add an SSH key to your GitHub account (or use an HTTPS
  token) with access granted by your Odoo Enterprise subscription / partnership.
  Use `SKIP_ENTERPRISE=1` for a community-only base.

To bootstrap a fresh machine, the tooling repo ships a setup script that creates
this base, clones Odoo CE 18/19 + Enterprise 18/19, builds the per-version
virtualenvs, and seeds `_data`/`_scripts`/`_concepts`, the base docs, and a
sample config:

```bash
cd ~/git/odoo-mcp-server
npm run setup-env          # or: ./scripts/setup_odoo_env.sh
```

Env vars: `ENTERPRISE_REMOTE=https` (HTTPS/token instead of SSH),
`SKIP_ENTERPRISE=1`, `FULL_CLONE=1` (full history vs shallow), `PYTHON=python3.11`,
`ODOO_BASE=/path`. The script is idempotent — re-running skips whatever exists.

Then create your first project config from the sample:

```bash
cp odoo-sample.conf odoo-myproject.conf   # edit db_name, addons_path, 18/19 markers
odoo switch myproject
```

## Layout

System directories are prefixed with `_` so they stand out from the project
addon symlinks (which have no prefix):

```
~/odoo/
  _odoo18/  _enterprise18/   Odoo Community + Enterprise 18 source
  _odoo19/  _enterprise19/   Odoo Community + Enterprise 19 source
  _venv18/  _venv19/         Python virtualenvs for 18 / 19
  _data/                     filestore + sessions
  _scripts/<project>/        ad-hoc helper scripts (test / seed / clean)
  _concepts/<project>/       exploratory / new-concept scripts (knowledge base)
  odoo.conf                  the ACTIVE config (a copy of one odoo-<project>.conf)
  odoo-<project>.conf        one config per project
  <project>                  symlink → ~/git/<repo>  (a project's custom addons)
  odoo.log   odoo.pid        log + PID of the running server
```

Each `<project>` (hhfbs, nellika, verita, tora, …) is a symlink to its repo
under `~/git/`.

### One base, both Odoo versions

There is no separate tree per Odoo version. **The active project decides whether
Odoo 18 or 19 runs**, via its config (`odoo-<project>.conf`): the `; odoo_src` /
`; python_venv` markers and the `addons_path` point at `_odoo18`/`_venv18` or
`_odoo19`/`_venv19`. So switching project can also switch the running version.
Today only **verita** runs on 19; the rest run on 18. Run `odoo addons-dir` to
see which is active (a path under `_odoo19/` means CE 19).

## The `odoo` command

`odoo` is installed in `~/.local/bin` and works from any directory — it always
targets this base. It is the recommended way to drive Odoo; its module commands
filter the noisy logs down to errors/warnings.

```bash
odoo status                  # is Odoo running?
odoo start | stop | restart  # server control
odoo list                    # available projects + the active one
odoo switch <project>        # activate a project's config and restart
odoo update <modules>        # update module(s) (comma-separated) and restart
odoo install <modules>       # install module(s)
odoo frontend <modules>      # update web assets and restart
odoo test [modules]          # run tests (add --tags <tags> to filter)
odoo logs                    # tail odoo.log (add --lines <n> for the full log)
odoo shell                   # print the command to open an interactive shell
odoo addons-dir              # which core source is active (_odoo18 / _odoo19)
```

Module commands print a concise summary; on a clean run you get
`✓ Operation completed successfully`. When you need the raw log, use
`odoo logs --lines 200`. For the unfiltered engine itself, use `manage_odoo`
(same commands, raw output).

## Switching projects

```bash
odoo list                    # see what's available and what's active
odoo switch nellika          # make nellika the active project, restart Odoo
```

Switching copies `odoo-nellika.conf` to `odoo.conf`, so the project's database,
addons, and Odoo version all change together.

## Loading a database

```bash
odoo import <file>                 # Odoo/odoo.sh .zip, .sql, .sql.gz, or pg_dump .dump
odoo import <file> --db-only       # restore the database only, skip the filestore
odoo import prod.zip --neutralize  # import a production backup, then neutralize it
odoo fresh                         # wipe to an empty database (base installs on start)
odoo fresh --init base,sale        # empty database, initialize base + sale
```

These act on the **active** project's database and are **destructive** (they drop
the current database). `--neutralize` disables outgoing mail, scheduled actions,
and payment providers — use it for production / odoo.sh `exact_fs` backups so a
dev copy can't reach the outside world.

## Helper scripts and concepts

Keep ad-hoc scripts out of the addon repos and the base root:

- **`_scripts/<project>/`** — scripts to test, seed, clean, or fix up data.
- **`_concepts/<project>/`** — exploratory / new-concept scripts, including one-off
  XML-RPC tools. Treat this as a growing knowledge base of "how we did X".

Start every script with a short header comment of what it does — at most 3 lines,
each ≤80 characters.

## Using Odoo with Claude

- **Claude Code** has an `odoo-manage` skill: just ask ("start odoo", "update
  module X", "switch to nellika", "run tests for sale") and it uses the same
  commands shown here.
- **Claude Desktop** has the `odoo` MCP server, exposing the same operations as
  tools.

## The tooling itself

The `odoo` / `manage_odoo` commands, the skill, and the MCP server all come from
`~/git/odoo-mcp-server`. To (re)install on this or another machine:

```bash
git clone https://github.com/dannyg-sys/odoo-mcp-server.git ~/git/odoo-mcp-server
cd ~/git/odoo-mcp-server && npm install && npm run build && npm run setup
```
