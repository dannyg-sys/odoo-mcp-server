#!/bin/bash
#
# stream_odoo.sh — stream a remote nellika.sh / tcff Odoo DB + filestore straight
# into the LOCAL Odoo dev environment at ~/odoo, without intermediate dump files.
#
# Read-only on the remote (ssh + sourcing ~/scripts/odoo.env). Destructive on the
# local ACTIVE project: it drops and recreates the active database and replaces
# the active filestore. DB stream and filestore stream run in parallel.
#
# Usage: stream_odoo.sh <remote_ssh_host> [options]
#   --remote-db <name>        override the discovered remote db name
#   --remote-data-dir <path>  override the discovered remote data_dir
#   --db-only                 stream the database only (skip filestore)
#   --filestore-only          stream the filestore only (skip database)
#   --neutralize              run odoo-bin neutralize after the restore
#   --no-start                do not start local Odoo afterwards
#   --yes | -y                skip the confirmation prompt
#   -h | --help               show this help

set -euo pipefail

ODOO_BASE="${ODOO_BASE:-$HOME/odoo}"
ODOO_CLI="${ODOO_CLI:-node __ODOO_CLI__}"
PG17_BIN="/Applications/Postgres.app/Contents/Versions/17/bin"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

err() { echo "Error: $*" >&2; exit 1; }

# Echo a command (project CLAUDE.md wants commands shown) then run it.
run() { echo "+ $*" >&2; "$@"; }

# ---- parse args -------------------------------------------------------------
REMOTE_HOST=""
REMOTE_DB=""
REMOTE_DATA_DIR=""
DB_ONLY=0
FILESTORE_ONLY=0
NEUTRALIZE=0
NO_START=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --remote-db)       REMOTE_DB="${2:-}"; shift ;;
        --remote-data-dir) REMOTE_DATA_DIR="${2:-}"; shift ;;
        --db-only)         DB_ONLY=1 ;;
        --filestore-only)  FILESTORE_ONLY=1 ;;
        --neutralize)      NEUTRALIZE=1 ;;
        --no-start)        NO_START=1 ;;
        --yes|-y)          ASSUME_YES=1 ;;
        -h|--help)         usage; exit 0 ;;
        -*)                err "unknown option '$1' (see --help)" ;;
        *)                 if [ -z "$REMOTE_HOST" ]; then REMOTE_HOST="$1"; else err "unexpected argument '$1'"; fi ;;
    esac
    shift
done

[ -n "$REMOTE_HOST" ] || { usage; exit 1; }
[ "$DB_ONLY" = 1 ] && [ "$FILESTORE_ONLY" = 1 ] && err "--db-only and --filestore-only are mutually exclusive"

# ---- locate local tools -----------------------------------------------------
# Prefer Postgres.app 17 client tools (the local cluster is PG17 after the
# migration, matching remote prod); fall back to whatever is on PATH.
pgtool() {
    local name="$1"
    if [ -x "$PG17_BIN/$name" ]; then echo "$PG17_BIN/$name"; else echo "$name"; fi
}
PG_RESTORE=$(pgtool pg_restore)
CREATEDB=$(pgtool createdb)
DROPDB=$(pgtool dropdb)
PSQL=$(pgtool psql)

# pv is optional — fall back to a plain cat pipe if missing.
if command -v pv >/dev/null 2>&1; then PV="pv"; elif [ -x /opt/homebrew/bin/pv ]; then PV="/opt/homebrew/bin/pv"; else PV="cat"; fi

# ---- read the ACTIVE local project from odoo.conf ---------------------------
cd "$ODOO_BASE" || err "Odoo base directory not found: $ODOO_BASE"
[ -f "$ODOO_BASE/odoo.conf" ] || err "no active odoo.conf in $ODOO_BASE (run 'odoo switch <project>' first)"

conf_get() { grep -E "^${1}[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' '; }
conf_marker() { grep -E "^;[[:space:]]*${1}[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' '; }

LOCAL_DB=$(conf_get db_name)
LOCAL_USER=$(conf_get db_user)
LOCAL_HOST=$(conf_get db_host)
LOCAL_PORT=$(conf_get db_port)
FILESTORE_CONF=$(conf_get filestore)
ODOO_SRC=$(conf_marker odoo_src); ODOO_SRC="${ODOO_SRC:-_odoo18}"
PYTHON_VENV=$(conf_marker python_venv); PYTHON_VENV="${PYTHON_VENV:-_venv18}"

[ -n "$LOCAL_DB" ]   || err "could not read db_name from odoo.conf"
[ -n "$LOCAL_USER" ] || err "could not read db_user from odoo.conf"
[ -n "$FILESTORE_CONF" ] || FILESTORE_CONF="./_data/filestore"

# Resolve the filestore dir against the base (it is typically a relative path).
case "$FILESTORE_CONF" in
    /*) LOCAL_FILESTORE_DIR="$FILESTORE_CONF" ;;
    *)  LOCAL_FILESTORE_DIR="$ODOO_BASE/${FILESTORE_CONF#./}" ;;
esac
LOCAL_FILESTORE_TARGET="$LOCAL_FILESTORE_DIR/$LOCAL_DB"

# psql/createdb/dropdb connection args from the active conf.
PG_CONN=(-U "$LOCAL_USER")
[ -n "$LOCAL_HOST" ] && PG_CONN+=(-h "$LOCAL_HOST")
[ -n "$LOCAL_PORT" ] && PG_CONN+=(-p "$LOCAL_PORT")

# ---- discover the remote db + data_dir (read-only) --------------------------
if [ -z "$REMOTE_DB" ] || [ -z "$REMOTE_DATA_DIR" ]; then
    echo "Discovering remote env on $REMOTE_HOST (read-only)..." >&2
    DISCOVERED=$(ssh "$REMOTE_HOST" '. ~/scripts/odoo.env; echo "$odoo_db|$data_dir"') \
        || err "ssh discovery failed on $REMOTE_HOST (is ~/scripts/odoo.env present?)"
    [ -z "$REMOTE_DB" ]       && REMOTE_DB="${DISCOVERED%%|*}"
    [ -z "$REMOTE_DATA_DIR" ] && REMOTE_DATA_DIR="${DISCOVERED##*|}"
fi
[ -n "$REMOTE_DB" ]       || err "could not discover remote odoo_db (use --remote-db)"
[ -n "$REMOTE_DATA_DIR" ] || err "could not discover remote data_dir (use --remote-data-dir)"

# ---- summary + confirmation -------------------------------------------------
DO_DB=1; DO_FS=1
[ "$FILESTORE_ONLY" = 1 ] && DO_DB=0
[ "$DB_ONLY" = 1 ] && DO_FS=0

echo "==================================================================="
echo " Stream remote Odoo  ->  LOCAL dev (DESTRUCTIVE on local)"
echo "-------------------------------------------------------------------"
echo " Remote host        : $REMOTE_HOST"
echo " Remote db          : $REMOTE_DB"
echo " Remote data_dir    : $REMOTE_DATA_DIR"
echo " Remote filestore   : $REMOTE_DATA_DIR/filestore/$REMOTE_DB"
echo "-------------------------------------------------------------------"
echo " Local base         : $ODOO_BASE"
echo " Local db (target)  : $LOCAL_DB (user $LOCAL_USER)"
echo " Local filestore    : $LOCAL_FILESTORE_TARGET"
echo " pg client tools    : ${PG_RESTORE%/*}"
echo " progress (pv)      : $PV"
echo "-------------------------------------------------------------------"
echo " Database stream    : $([ "$DO_DB" = 1 ] && echo yes || echo SKIPPED)"
echo " Filestore stream   : $([ "$DO_FS" = 1 ] && echo yes || echo SKIPPED)"
echo " Neutralize after   : $([ "$NEUTRALIZE" = 1 ] && echo yes || echo no)"
echo " Start Odoo after   : $([ "$NO_START" = 1 ] && echo no || echo yes)"
echo "==================================================================="

if [ "$ASSUME_YES" != 1 ]; then
    printf "Proceed? This will DROP local db '%s' and replace its filestore. [y/N] " "$LOCAL_DB"
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# ---- stop local Odoo --------------------------------------------------------
echo ">> Stopping local Odoo..." >&2
run $ODOO_CLI stop || echo "Warning: 'odoo stop' reported a problem (continuing)." >&2

# ---- the two streaming jobs -------------------------------------------------
stream_db() {
    echo ">> [db] terminating connections to $LOCAL_DB ..." >&2
    "$PSQL" "${PG_CONN[@]}" -d postgres -v ON_ERROR_STOP=1 -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$LOCAL_DB' AND pid <> pg_backend_pid();" >/dev/null

    echo ">> [db] dropdb + createdb $LOCAL_DB ..." >&2
    "$DROPDB" "${PG_CONN[@]}" --if-exists "$LOCAL_DB"
    "$CREATEDB" "${PG_CONN[@]}" -O "$LOCAL_USER" "$LOCAL_DB"

    echo ">> [db] creating extensions (unaccent, pg_trgm) ..." >&2
    "$PSQL" "${PG_CONN[@]}" -d "$LOCAL_DB" -v ON_ERROR_STOP=1 \
        -c "CREATE EXTENSION IF NOT EXISTS unaccent;" \
        -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" \
        -c "ALTER FUNCTION unaccent(text) IMMUTABLE;" >/dev/null

    echo ">> [db] streaming pg_dump '$REMOTE_DB' | $PV | pg_restore -> '$LOCAL_DB' ..." >&2
    set -o pipefail
    ssh "$REMOTE_HOST" '. ~/scripts/odoo.env; pg_dump -Fc --no-owner --no-privileges "$odoo_db"' \
        | "$PV" \
        | "$PG_RESTORE" --no-owner "${PG_CONN[@]}" -d "$LOCAL_DB" \
        || echo ">> [db] pg_restore reported errors (often harmless ownership/role notices)." >&2
    echo ">> [db] done." >&2
}

stream_filestore() {
    echo ">> [fs] preparing $LOCAL_FILESTORE_DIR ..." >&2
    mkdir -p "$LOCAL_FILESTORE_DIR"

    echo ">> [fs] streaming tar of remote filestore '$REMOTE_DB' -> $LOCAL_FILESTORE_DIR ..." >&2
    set -o pipefail
    ssh "$REMOTE_HOST" '. ~/scripts/odoo.env; tar -C "$data_dir/filestore" -zc "$odoo_db"' \
        | "$PV" \
        | tar -C "$LOCAL_FILESTORE_DIR" -zx

    if [ "$REMOTE_DB" != "$LOCAL_DB" ]; then
        echo ">> [fs] renaming extracted '$REMOTE_DB' -> '$LOCAL_DB' ..." >&2
        [ -d "$LOCAL_FILESTORE_TARGET" ] && rm -rf "$LOCAL_FILESTORE_TARGET"
        mv "$LOCAL_FILESTORE_DIR/$REMOTE_DB" "$LOCAL_FILESTORE_TARGET"
    fi
    echo ">> [fs] done." >&2
}

# Run both in parallel as background jobs; collect their exit codes.
DB_PID=""; FS_PID=""
DB_RC=0; FS_RC=0

if [ "$DO_DB" = 1 ]; then stream_db & DB_PID=$!; fi
if [ "$DO_FS" = 1 ]; then stream_filestore & FS_PID=$!; fi

if [ -n "$DB_PID" ]; then wait "$DB_PID" || DB_RC=$?; fi
if [ -n "$FS_PID" ]; then wait "$FS_PID" || FS_RC=$?; fi

[ "$DB_RC" -ne 0 ] && echo "Error: database stream failed (rc=$DB_RC)" >&2
[ "$FS_RC" -ne 0 ] && echo "Error: filestore stream failed (rc=$FS_RC)" >&2
if [ "$DB_RC" -ne 0 ] || [ "$FS_RC" -ne 0 ]; then
    err "one or more streams failed; local Odoo left stopped."
fi

# ---- neutralize (optional) --------------------------------------------------
if [ "$NEUTRALIZE" = 1 ]; then
    echo ">> Neutralizing database (disable mail, crons, payment providers) ..." >&2
    run "$ODOO_BASE/$PYTHON_VENV/bin/python3" "$ODOO_BASE/$ODOO_SRC/odoo-bin" neutralize -c odoo.conf \
        || echo "Warning: neutralize step reported errors." >&2
fi

# ---- start (optional) -------------------------------------------------------
if [ "$NO_START" = 1 ]; then
    echo "Done (Odoo not started; --no-start given)."
else
    echo ">> Starting local Odoo..." >&2
    run $ODOO_CLI start
    echo "Done."
fi
