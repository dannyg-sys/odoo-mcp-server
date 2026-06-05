# Changelog

All notable changes to the odoo-mcp-server tooling are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- **`stream` — pull a remote Odoo deployment into the active local project.**
  Streams a remote nellika.sh / tcff database + filestore over SSH straight into
  the active project, with no intermediate dump files: `pg_dump -Fc | pg_restore`
  and `tar | tar` run **in parallel**. Discovers the remote `odoo_db`/`data_dir`
  from the remote `~/scripts/odoo.env`; read-only on the remote, destructive on
  the local active DB/filestore. Mirrors the tcff `get_production_db` /
  `get_production_filestore` recipe.
  - **One implementation, three entry points** (no duplicated logic): the verb
    `stream_remote_odoo` lives only in `scripts/manage_odoo.sh` and reuses the
    existing `kill_odoo`/`start_odoo`/`neutralize_db` helpers. Exposed as:
    - CLI: `odoo stream <host> [--remote-db|--remote-data-dir|--db-only|--filestore-only|--neutralize|--no-start|--yes]`
    - MCP: `odoo_project` action `stream` (`remoteHost`, `remoteDb`, `remoteDataDir`,
      `dbOnly`, `filestoreOnly`, `neutralize`, `noStart`)
    - Skill: the **`odoo-stream`** Claude Code skill (`skill-stream/`), a thin
      wrapper that `exec`s the engine verb.
  - Requires the local Postgres major ≥ the remote's (production is PG17). Prefers
    the Postgres.app 17 client tools, falling back to PATH.

### Changed
- `executeCommand` (core.ts) takes an optional `timeoutMs`; `streamDatabase` uses
  a 30-min timeout (a prod stream can exceed the default 5 min) and always passes
  `--yes` (the non-TTY CLI/MCP call is itself the confirmation).
- `install.sh` renders + installs the `odoo-stream` skill (SKILL.md + wrapper)
  alongside `odoo-manage`; README/Features document `stream`.

### Fixed
- **Parallel-SSH collision that silently produced an empty database.** The two
  concurrent `ssh` sessions to the same host shared a ControlMaster socket; one
  lost the race and yielded an empty `pg_dump`, which `|| echo "...harmless..."`
  masked (db restored with 0 rows). Each streaming `ssh` now uses
  `-o ControlPath=none`, and `PIPESTATUS` distinguishes a real `pg_dump`/ssh
  failure (abort) from harmless `pg_restore` ownership/role notices.
