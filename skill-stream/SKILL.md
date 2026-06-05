---
name: odoo-stream
description: Stream a remote nellika.sh / tcff Odoo database + filestore straight into the LOCAL Odoo dev environment under ~/odoo, with no intermediate dump files. Use when the user asks to stream/pull a production (or staging/test) database into local Odoo, refresh local Odoo from the nellika.sh deployment, or pull nellika/tcff production db+filestore locally. It targets the ACTIVE local project and is destructive on the local DB/filestore.
tools:
  - Bash(__STREAM_SH__:*)
  - Bash(ssh:*)
  - Bash(node:*)
---

# Stream a remote Odoo DB + filestore into local dev

Pulls a remote nellika.sh / tcff Odoo deployment's database and filestore
directly into the LOCAL dev environment at `~/odoo` by **streaming over SSH** —
`pg_dump | pg_restore` and `tar | tar`, with no intermediate dump files on
disk. The DB and filestore transfers run **in parallel**.

The single deliverable is the script:

```
__STREAM_SH__
```

## What it does

1. **Discovers the remote** (read-only): one ssh that sources the remote
   `~/scripts/odoo.env` to read `odoo_db` and `data_dir`. The remote filestore
   is `$data_dir/filestore/$odoo_db`. PGUSER/PGPASSWORD for the remote come from
   that same env file, so `pg_dump` authenticates there.
2. **Reads the ACTIVE local project** from `~/odoo/odoo.conf` (`db_name`,
   `db_user`, `db_host`, `db_port`, `filestore`). Refuses to run if `odoo.conf`
   is missing. Local filestore target = `<filestore>/<db_name>` resolved against
   `~/odoo`.
3. **Stops local Odoo** (via the `odoo` CLI).
4. **DB stream:** terminate connections, `dropdb --if-exists`, `createdb -O <user>`,
   create the `unaccent` + `pg_trgm` extensions and
   `ALTER FUNCTION unaccent(text) IMMUTABLE`, then
   `ssh <host> '. ~/scripts/odoo.env; pg_dump -Fc --no-owner --no-privileges "$odoo_db"' | pv | pg_restore --no-owner -d <db>`.
5. **Filestore stream (in parallel):**
   `ssh <host> '. ~/scripts/odoo.env; tar -C "$data_dir/filestore" -zc "$odoo_db"' | pv | tar -zx`,
   then rename the extracted `$odoo_db` dir to the local `<db_name>`.
6. Optionally **neutralize**, then **start** local Odoo.

## Prerequisites

- **Local Postgres major version must be >= the remote's.** Remote
  **production is PG17**, so the local cluster must be PG17. The script uses the
  Postgres.app 17 client tools at
  `/Applications/Postgres.app/Contents/Versions/17/bin` (pg_restore, createdb,
  dropdb, psql) when present, else falls back to PATH.
- `pv` (progress bar) is **optional** — falls back to a plain pipe.
- SSH access configured in `~/.ssh/config.d/`. Hosts follow the pattern
  `<deployment>_<env>_odoo`, e.g. `nellika_production_odoo`,
  `nellika_staging_odoo`, `nellika_test_odoo`, `tcff_production_odoo`, …
- The remote must have `~/scripts/odoo.env` exporting `odoo_db`, `data_dir`,
  `PGUSER`, `PGPASSWORD`.

## It targets the ACTIVE project

The local target (DB name, user, filestore) comes from the **active**
`~/odoo/odoo.conf`. Switch first if needed:

```bash
node __ODOO_CLI__ switch nellika
```

Then stream into that project's DB. The streamed remote DB is renamed to the
local `db_name` automatically (DB restore is name-agnostic; the filestore dir is
renamed from `$odoo_db` to `<db_name>`).

## Usage

```bash
__STREAM_SH__ <remote_ssh_host> [options]
```

Options:

| Option | Effect |
|---|---|
| `--remote-db <name>` | Override the discovered remote db name |
| `--remote-data-dir <path>` | Override the discovered remote data_dir |
| `--db-only` | Stream the database only (skip filestore) |
| `--filestore-only` | Stream the filestore only (skip database) |
| `--neutralize` | Run `odoo-bin neutralize` after restore (recommended for production sources) |
| `--no-start` | Do not start local Odoo afterwards |
| `--yes` / `-y` | Skip the confirmation prompt |
| `-h` / `--help` | Show usage |

Before any destructive work it prints a summary (remote host, remote db, local
target db, local filestore path) and asks for confirmation unless `--yes`.

## Examples

```bash
# Pull production into the active project, neutralize, then start (with prompt)
__STREAM_SH__ nellika_production_odoo --neutralize

# Pull staging, no prompt, leave Odoo stopped
__STREAM_SH__ nellika_staging_odoo --yes --no-start

# Refresh only the filestore from production
__STREAM_SH__ nellika_production_odoo --filestore-only

# Pull a tcff db only, overriding the discovered remote db name
__STREAM_SH__ tcff_production_odoo --db-only --remote-db tcff_production
```

## Safety notes

- **Destructive on local:** drops and recreates the active database and replaces
  its filestore. Read-only on the remote.
- Always `--neutralize` when the source is **production** so the dev copy can't
  send mail / run crons / hit payment providers.
- If either stream fails, both jobs are waited on, the failure is reported, and
  local Odoo is left stopped (not restarted).
