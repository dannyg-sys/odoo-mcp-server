#!/bin/bash

# Resolve the Odoo base directory. Default is ~/odoo; ODOO_BASE overrides it
# (the MCP server / CLI set this so both stay in sync). A directory only counts
# as a base if it has an odoo.conf or at least one odoo-<project>.conf — matching
# core.ts's isOdooBase() — otherwise we fall back to the legacy ~/git/odoo18
# location during the transition. Every other path here is relative to the base.
ODOO_BASE="${ODOO_BASE:-$HOME/odoo}"
if [ ! -f "$ODOO_BASE/odoo.conf" ] && ! ls "$ODOO_BASE"/odoo-*.conf >/dev/null 2>&1; then
    ODOO_BASE="$HOME/git/odoo18"
fi
cd "$ODOO_BASE" || { echo "Error: Odoo base directory not found: $ODOO_BASE" >&2; exit 1; }

# Read odoo source dir from active conf (marker: "; odoo_src = ..."), default "_odoo18"
get_odoo_src() {
    local src
    src=$(grep -E "^;[[:space:]]*odoo_src[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    echo "${src:-_odoo18}"
}

# Read python venv dir from active conf (marker: "; python_venv = ..."), default "_venv18"
get_python_venv() {
    local v
    v=$(grep -E "^;[[:space:]]*python_venv[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    echo "${v:-_venv18}"
}

# Function to kill existing Odoo process (matches any odoo source dir)
kill_odoo() {
    pkill -f "odoo-bin -c odoo.conf"
    sleep 2
}

# Function to start Odoo
start_odoo() {
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)

    # Read database config from odoo.conf for nell_scb_lib telemetry
    export PGDATABASE=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGHOST=$(grep "^db_host" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGPORT=$(grep "^db_port" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGUSER=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGPASSWORD=$(grep "^db_password" odoo.conf | cut -d'=' -f2 | tr -d ' ')

    # Enable SCB-C debug logging (set to 1 to enable detailed logging)
    export SCB_DEBUG=1
    export DEBUG_SCB=1

    # Start Odoo in the background
    nohup ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf > odoo.log 2>&1 &

    # Get the PID of the new Odoo process
    ODOO_PID=$!

    # Save the PID to a file
    echo $ODOO_PID > odoo.pid

    echo "Odoo started with PID: $ODOO_PID (src=${ODOO_SRC}, venv=${PYTHON_VENV})"
    echo "Logs are being written to odoo.log"
}

# Function to upgrade modules (updates module and restarts Odoo)
upgrade_modules() {
    local modules="$1"
    local error_only="$2"
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)

    echo "Upgrading modules: $modules (includes restart)"

    # Update the modules first
    if [ "$error_only" = "--error-only" ]; then
        ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf -u "$modules" --no-http --stop-after-init --log-level=error
    else
        ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf -u "$modules" --no-http --stop-after-init --log-level=warn
    fi

    # Then restart Odoo to reload frontend assets (quietly)
    kill_odoo >/dev/null 2>&1

    # Read database config from odoo.conf for nell_scb_lib telemetry
    export PGDATABASE=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGHOST=$(grep "^db_host" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGPORT=$(grep "^db_port" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGUSER=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    export PGPASSWORD=$(grep "^db_password" odoo.conf | cut -d'=' -f2 | tr -d ' ')

    # Enable SCB-C debug logging (set to 1 to enable detailed logging)
    export SCB_DEBUG=1
    export DEBUG_SCB=1

    nohup ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf > odoo.log 2>&1 &
    ODOO_PID=$!
    echo $ODOO_PID > odoo.pid
    echo "Modules upgraded and server restarted (PID: $ODOO_PID)"
}

# Function to install modules
install_modules() {
    local modules="$1"
    local error_only="$2"
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)

    echo "Installing modules: $modules"

    if [ "$error_only" = "--error-only" ]; then
        ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf -i "$modules" --no-http --stop-after-init --log-level=error
    else
        ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf -i "$modules" --no-http --stop-after-init --log-level=warn
    fi
}

# Function to run tests
run_tests() {
    local modules="$1"
    local test_tags="$2"
    local error_only="$3"
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)

    # Determine log level based on error_only flag
    local log_level="warn"
    if [ "$error_only" = "--error-only" ]; then
        log_level="error"
    fi

    if [ -z "$modules" ]; then
        echo "Running all tests..."
        if [ -n "$test_tags" ]; then
            echo "Test tags: $test_tags"
            ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf --test-enable --test-tags="$test_tags" --no-http --stop-after-init --log-level=$log_level
        else
            ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf --test-enable --no-http --stop-after-init --log-level=$log_level
        fi
    else
        echo "Running tests for modules: $modules"
        if [ -n "$test_tags" ]; then
            echo "Test tags: $test_tags"
            ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf --test-enable --test-tags="$test_tags" -i "$modules" --no-http --stop-after-init --log-level=$log_level
        else
            ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin -c odoo.conf --test-enable -i "$modules" --no-http --stop-after-init --log-level=$log_level
        fi
    fi
}

# Function to start Odoo shell
start_shell() {
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)
    echo "Starting Odoo shell... (src=${ODOO_SRC}, venv=${PYTHON_VENV})"
    echo "Available variables: env, registry, cr"
    echo "Example: env['res.users'].search([('login', '=', 'admin')])"
    echo "--------------------------------------------------"
    ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin shell -c odoo.conf --shell-interface=ipython --no-http
}

# Function to check if Odoo is running
check_odoo() {
    if [ -f odoo.pid ]; then
        PID=$(cat odoo.pid)
        if ps -p $PID > /dev/null; then
            echo "Odoo is running with PID: $PID"
            return 0
        else
            echo "Odoo is not running (stale PID file found)"
            rm odoo.pid
            return 1
        fi
    else
        echo "Odoo is not running"
        return 1
    fi
}

# Function to list available configurations
list_config() {
    echo "Available configurations:"
    ls -1 odoo-*.conf 2>/dev/null | sed 's/^odoo-//' | sed 's/\.conf$//' || echo "No configuration files found"
    echo
    if [ -f "odoo.conf" ]; then
        echo "Current configuration (odoo.conf):"
        local current_db=$(grep "^db_name" odoo.conf 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
        if [ -n "$current_db" ]; then
            echo "  Database: $current_db"
        fi
    fi
}

# Function to switch configuration
switch_config() {
    local project="$1"
    local config_file="odoo-${project}.conf"
    
    # Check if the config file exists
    if [ ! -f "$config_file" ]; then
        echo "Error: Configuration file '$config_file' not found"
        echo
        echo "Available configurations:"
        find . -maxdepth 1 -name "*.conf" -not -name "odoo.conf" | sed 's|./||' | sed 's|\.conf$||' | sort
        return 1
    fi
    
    # Stop Odoo if running
    if check_odoo > /dev/null 2>&1; then
        echo "Stopping Odoo..."
        kill_odoo
        rm -f odoo.pid
    fi
    
    # Backup the current odoo.conf file
    if [ -f "odoo.conf" ]; then
        echo "Backing up current odoo.conf to odoo.conf.prev"
        cp odoo.conf odoo.conf.prev
    fi
    
    # Copy the project config file to odoo.conf
    echo "Switching to '$project' configuration"
    cp "$config_file" odoo.conf
    
    echo "Done! Configuration switched to '$project'"
    echo "Starting Odoo with new configuration..."
    start_odoo
}

# Neutralize the active database: disable outgoing mail servers, scheduled
# actions, payment providers, etc. Use after importing a production / odoo.sh
# "exact" backup so a dev copy can't act on the outside world.
neutralize_db() {
    local ODOO_SRC=$(get_odoo_src)
    local PYTHON_VENV=$(get_python_venv)
    echo "Neutralizing database (disabling mail, crons, payment providers)..."
    ${PYTHON_VENV}/bin/python3 ${ODOO_SRC}/odoo-bin neutralize -c odoo.conf
}

# Import a database backup into the ACTIVE project's database (db_name/db_user/
# filestore are read from the active odoo.conf). Supported formats, auto-detected
# by extension:
#   *.zip            Odoo / odoo.sh backup: top-level dump.sql [+ filestore/]
#   *.sql            plain SQL dump (database only)
#   *.sql.gz | *.gz  gzipped SQL dump (database only)
#   *.dump           pg_dump custom-format dump (pg_restore; database only)
# Flags: --db-only (skip filestore even if present), --neutralize (run neutralize
# after import), --no-start (don't start Odoo afterwards).
import_backup() {
    local backup_file=""
    local db_only=0 neutralize=0 no_start=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --db-only)    db_only=1 ;;
            --neutralize) neutralize=1 ;;
            --no-start)   no_start=1 ;;
            -*)           echo "Error: unknown option '$1'" >&2; return 1 ;;
            *)            if [ -z "$backup_file" ]; then backup_file="$1"; else echo "Error: unexpected argument '$1'" >&2; return 1; fi ;;
        esac
        shift
    done

    if [ -z "$backup_file" ]; then
        echo "Error: No backup file specified"
        echo "Usage: $0 import FILE [--db-only] [--neutralize] [--no-start]"
        echo "  FILE: .zip (Odoo/odoo.sh), .sql, .sql.gz/.gz, or pg_dump .dump"
        return 1
    fi
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file '$backup_file' not found"
        return 1
    fi

    # Settings from the active odoo.conf
    local db_name=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local db_user=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local filestore_dir=$(grep "^filestore" odoo.conf | cut -d'=' -f2 | tr -d ' ')

    # Detect and VALIDATE the format up front — extract the zip and confirm
    # dump.sql BEFORE touching the database, so a bad file never leaves us with
    # a dropped database.
    local tmp_dir="" fmt=""
    case "$backup_file" in
        *.zip)
            fmt="zip"
            tmp_dir=$(mktemp -d)
            echo "Extracting zip to $tmp_dir ..."
            unzip -q "$backup_file" -d "$tmp_dir" || { echo "Failed to extract backup"; rm -rf "$tmp_dir"; return 1; }
            if [ ! -f "$tmp_dir/dump.sql" ]; then
                echo "Error: dump.sql not found at the top level of the zip"; rm -rf "$tmp_dir"; return 1
            fi
            ;;
        *.dump)        fmt="dump" ;;
        *.sql.gz|*.gz) fmt="sqlgz" ;;
        *.sql)         fmt="sql" ;;
        *)
            echo "Error: unrecognized backup type for '$backup_file'"
            echo "Supported: .zip, .sql, .sql.gz/.gz, .dump"
            return 1
            ;;
    esac

    echo "Importing into the active project:"
    echo "  Database:  $db_name (user $db_user)"
    echo "  Filestore: $filestore_dir/$db_name"
    echo "  Backup:    $backup_file"
    [ "$db_only" = "1" ] && echo "  Mode:      database only (filestore skipped)"

    # Stop Odoo if running
    if check_odoo > /dev/null 2>&1; then
        echo "Stopping Odoo..."
        kill_odoo
        rm -f odoo.pid
    fi

    # (Re)create the target database (the backup is already validated above)
    echo "Dropping database $db_name if it exists..."
    dropdb -U "$db_user" "$db_name" 2>/dev/null
    echo "Creating database $db_name..."
    createdb -U "$db_user" "$db_name" || { echo "Failed to create database"; [ -n "$tmp_dir" ] && rm -rf "$tmp_dir"; return 1; }

    # Restore according to the detected format
    case "$fmt" in
        zip)
            echo "Restoring database from dump.sql ..."
            psql -U "$db_user" -d "$db_name" < "$tmp_dir/dump.sql" > /dev/null || { echo "Failed to import database"; rm -rf "$tmp_dir"; return 1; }
            if [ "$db_only" != "1" ] && [ -d "$tmp_dir/filestore" ]; then
                echo "Installing filestore -> $filestore_dir/$db_name ..."
                [ -d "$filestore_dir/$db_name" ] && rm -rf "$filestore_dir/$db_name"
                mkdir -p "$filestore_dir"
                mv "$tmp_dir/filestore" "$filestore_dir/$db_name" || { echo "Failed to move filestore"; rm -rf "$tmp_dir"; return 1; }
            elif [ "$db_only" != "1" ]; then
                echo "Note: no filestore/ in backup (database-only)."
            fi
            rm -rf "$tmp_dir"
            ;;
        dump)
            echo "Restoring pg_dump custom-format dump (pg_restore)..."
            pg_restore --no-owner --no-privileges -U "$db_user" -d "$db_name" "$backup_file" \
                || echo "Note: pg_restore reported errors (often harmless ownership/role notices)."
            ;;
        sqlgz)
            echo "Restoring gzipped SQL dump..."
            gunzip -c "$backup_file" | psql -U "$db_user" -d "$db_name" > /dev/null || { echo "Failed to import database"; return 1; }
            ;;
        sql)
            echo "Restoring SQL dump..."
            psql -U "$db_user" -d "$db_name" < "$backup_file" > /dev/null || { echo "Failed to import database"; return 1; }
            ;;
    esac

    echo "Database import completed."

    if [ "$neutralize" = "1" ]; then
        neutralize_db || echo "Warning: neutralize step reported errors"
    fi

    if [ "$no_start" = "1" ]; then
        echo "Done (Odoo not started; --no-start given)."
    else
        echo "Starting Odoo with imported database..."
        start_odoo
    fi
}

# Create a FRESH database for the ACTIVE project: drop the existing database and
# its filestore, create a new one, and initialize it. A new database must be
# initialized with -i (Odoo does NOT auto-initialize on a normal start), so we
# always install at least base. Flags: --init <modules> to install extra modules
# on top of base, --no-start to skip the restart.
create_fresh_db() {
    local init_modules="" no_start=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --init)     init_modules="$2"; shift ;;
            --no-start) no_start=1 ;;
            -*)         echo "Error: unknown option '$1'" >&2; return 1 ;;
            *)          echo "Error: unexpected argument '$1'" >&2; return 1 ;;
        esac
        shift
    done

    local db_name=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local db_user=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local filestore_dir=$(grep "^filestore" odoo.conf | cut -d'=' -f2 | tr -d ' ')

    echo "Creating a FRESH (empty) database for the active project:"
    echo "  Database:  $db_name (user $db_user)"
    echo "  Filestore: $filestore_dir/$db_name"
    [ -n "$init_modules" ] && echo "  Init:      $init_modules"

    # Stop Odoo if running
    if check_odoo > /dev/null 2>&1; then
        echo "Stopping Odoo..."
        kill_odoo
        rm -f odoo.pid
    fi

    echo "Dropping database $db_name if it exists..."
    dropdb -U "$db_user" "$db_name" 2>/dev/null

    if [ -d "$filestore_dir/$db_name" ]; then
        echo "Removing existing filestore..."
        rm -rf "$filestore_dir/$db_name"
    fi

    echo "Creating empty database $db_name..."
    createdb -U "$db_user" "$db_name" || { echo "Failed to create database"; return 1; }

    # A freshly created database is NOT auto-initialized on a normal server start
    # (Odoo would 500 with "ir_module_module does not exist"). Always initialize
    # at least base; install the requested modules on top.
    [ -z "$init_modules" ] && init_modules="base"
    echo "Initializing database with modules: $init_modules"
    install_modules "$init_modules"

    if [ "$no_start" = "1" ]; then
        echo "Done (Odoo not started; --no-start given)."
    else
        echo "Starting Odoo..."
        start_odoo
    fi
}

# Stream a remote nellika.sh / tcff Odoo deployment's database + filestore
# straight into the ACTIVE local project, over SSH, with no intermediate dump
# files. Read-only on the remote (ssh + sourcing ~/scripts/odoo.env). Destructive
# on the local active DB/filestore. DB and filestore transfers run in parallel.
# Requires the local Postgres major >= the remote's (production is PG17); prefers
# the Postgres.app 17 client tools, falling back to PATH. Usage:
#   stream HOST [--remote-db N] [--remote-data-dir P] [--db-only|--filestore-only]
#               [--neutralize] [--no-start] [--yes|-y]
stream_remote_odoo() {
    local remote_host="" remote_db="" remote_data_dir=""
    local db_only=0 filestore_only=0 neutralize=0 no_start=0 assume_yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --remote-db)       remote_db="${2:-}"; shift ;;
            --remote-data-dir) remote_data_dir="${2:-}"; shift ;;
            --db-only)         db_only=1 ;;
            --filestore-only)  filestore_only=1 ;;
            --neutralize)      neutralize=1 ;;
            --no-start)        no_start=1 ;;
            --yes|-y)          assume_yes=1 ;;
            -h|--help)
                echo "Usage: stream HOST [--remote-db N] [--remote-data-dir P] [--db-only|--filestore-only] [--neutralize] [--no-start] [--yes|-y]"
                echo "  Stream a remote nellika.sh/tcff Odoo db+filestore (over SSH) into the active project."
                echo "  HOST is an ssh host with ~/scripts/odoo.env (e.g. nellika_production_odoo, tcff_production_odoo)."
                return 0 ;;
            -*)                echo "Error: unknown option '$1'" >&2; return 1 ;;
            *)                 if [ -z "$remote_host" ]; then remote_host="$1"; else echo "Error: unexpected argument '$1'" >&2; return 1; fi ;;
        esac
        shift
    done

    [ -n "$remote_host" ] || { echo "Error: stream requires a remote ssh host" >&2; return 1; }
    [ "$db_only" = 1 ] && [ "$filestore_only" = 1 ] && { echo "Error: --db-only and --filestore-only are mutually exclusive" >&2; return 1; }

    # Active local project, read from odoo.conf (same inline style as fresh/import).
    local local_db local_user local_host local_port filestore_conf
    local_db=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local_user=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local_host=$(grep "^db_host" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local_port=$(grep "^db_port" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    filestore_conf=$(grep "^filestore" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    [ -n "$local_db" ]   || { echo "Error: could not read db_name from odoo.conf" >&2; return 1; }
    [ -n "$local_user" ] || { echo "Error: could not read db_user from odoo.conf" >&2; return 1; }
    [ -n "$filestore_conf" ] || filestore_conf="./_data/filestore"

    # Resolve the (usually relative) filestore dir against the base.
    local local_filestore_dir
    case "$filestore_conf" in
        /*) local_filestore_dir="$filestore_conf" ;;
        *)  local_filestore_dir="$ODOO_BASE/${filestore_conf#./}" ;;
    esac
    local local_filestore_target="$local_filestore_dir/$local_db"

    # psql/createdb/dropdb connection args from the active conf.
    local pg_conn=(-U "$local_user")
    [ -n "$local_host" ] && pg_conn+=(-h "$local_host")
    [ -n "$local_port" ] && pg_conn+=(-p "$local_port")

    # Prefer Postgres.app 17 client tools (PATH may be an older major that cannot
    # restore a pg17 dump); fall back to PATH.
    local pg17_bin="/Applications/Postgres.app/Contents/Versions/17/bin"
    local pg_restore createdb_bin dropdb_bin psql_bin
    pgtool() { if [ -x "$pg17_bin/$1" ]; then echo "$pg17_bin/$1"; else echo "$1"; fi; }
    pg_restore=$(pgtool pg_restore); createdb_bin=$(pgtool createdb)
    dropdb_bin=$(pgtool dropdb);     psql_bin=$(pgtool psql)

    # pv is optional — fall back to cat if missing.
    local pv
    if command -v pv >/dev/null 2>&1; then pv="pv"; elif [ -x /opt/homebrew/bin/pv ]; then pv="/opt/homebrew/bin/pv"; else pv="cat"; fi

    # Discover the remote db + data_dir (read-only) unless overridden.
    if [ -z "$remote_db" ] || [ -z "$remote_data_dir" ]; then
        echo "Discovering remote env on $remote_host (read-only)..." >&2
        local discovered
        discovered=$(ssh "$remote_host" '. ~/scripts/odoo.env; echo "$odoo_db|$data_dir"') \
            || { echo "Error: ssh discovery failed on $remote_host (is ~/scripts/odoo.env present?)" >&2; return 1; }
        [ -z "$remote_db" ]       && remote_db="${discovered%%|*}"
        [ -z "$remote_data_dir" ] && remote_data_dir="${discovered##*|}"
    fi
    [ -n "$remote_db" ]       || { echo "Error: could not discover remote odoo_db (use --remote-db)" >&2; return 1; }
    [ -n "$remote_data_dir" ] || { echo "Error: could not discover remote data_dir (use --remote-data-dir)" >&2; return 1; }

    local do_db=1 do_fs=1
    [ "$filestore_only" = 1 ] && do_db=0
    [ "$db_only" = 1 ] && do_fs=0

    echo "==================================================================="
    echo " Stream remote Odoo  ->  LOCAL dev (DESTRUCTIVE on local)"
    echo "-------------------------------------------------------------------"
    echo " Remote host        : $remote_host"
    echo " Remote db          : $remote_db"
    echo " Remote data_dir    : $remote_data_dir"
    echo " Remote filestore   : $remote_data_dir/filestore/$remote_db"
    echo "-------------------------------------------------------------------"
    echo " Local base         : $ODOO_BASE"
    echo " Local db (target)  : $local_db (user $local_user)"
    echo " Local filestore    : $local_filestore_target"
    echo " pg client tools    : ${pg_restore%/*}"
    echo " progress (pv)      : $pv"
    echo "-------------------------------------------------------------------"
    echo " Database stream    : $([ "$do_db" = 1 ] && echo yes || echo SKIPPED)"
    echo " Filestore stream   : $([ "$do_fs" = 1 ] && echo yes || echo SKIPPED)"
    echo " Neutralize after   : $([ "$neutralize" = 1 ] && echo yes || echo no)"
    echo " Start Odoo after   : $([ "$no_start" = 1 ] && echo no || echo yes)"
    echo "==================================================================="

    if [ "$assume_yes" != 1 ]; then
        printf "Proceed? This will DROP local db '%s' and replace its filestore. [y/N] " "$local_db"
        read -r ans
        case "$ans" in y|Y|yes|YES) ;; *) echo "Aborted."; return 0 ;; esac
    fi

    echo ">> Stopping local Odoo..." >&2
    kill_odoo; rm -f odoo.pid

    stream_db() {
        echo ">> [db] terminating connections to $local_db ..." >&2
        "$psql_bin" "${pg_conn[@]}" -d postgres -v ON_ERROR_STOP=1 -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$local_db' AND pid <> pg_backend_pid();" >/dev/null

        echo ">> [db] dropdb + createdb $local_db ..." >&2
        "$dropdb_bin" "${pg_conn[@]}" --if-exists "$local_db"
        "$createdb_bin" "${pg_conn[@]}" -O "$local_user" "$local_db"

        echo ">> [db] creating extensions (unaccent, pg_trgm) ..." >&2
        "$psql_bin" "${pg_conn[@]}" -d "$local_db" -v ON_ERROR_STOP=1 \
            -c "CREATE EXTENSION IF NOT EXISTS unaccent;" \
            -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" \
            -c "ALTER FUNCTION unaccent(text) IMMUTABLE;" >/dev/null

        echo ">> [db] streaming pg_dump '$remote_db' | $pv | pg_restore -> '$local_db' ..." >&2
        # ControlPath=none forces an independent ssh: the parallel db + filestore
        # sessions to the same host must NOT share a ControlMaster socket, or one
        # loses the race ("disabling multiplexing") and yields an EMPTY pg_dump.
        ssh -o ControlPath=none "$remote_host" '. ~/scripts/odoo.env; pg_dump -Fc --no-owner --no-privileges "$odoo_db"' \
            | "$pv" \
            | "$pg_restore" --no-owner "${pg_conn[@]}" -d "$local_db"
        local rc=("${PIPESTATUS[@]}")
        if [ "${rc[0]}" -ne 0 ]; then
            echo ">> [db] ERROR: remote pg_dump/ssh failed (rc=${rc[0]}) — empty dump, aborting." >&2
            return 1
        fi
        # A non-zero pg_restore is usually just ownership/role notices — tolerate.
        [ "${rc[2]:-0}" -ne 0 ] && echo ">> [db] pg_restore reported errors (often harmless ownership/role notices)." >&2
        echo ">> [db] done." >&2
    }

    stream_filestore() {
        echo ">> [fs] preparing $local_filestore_dir ..." >&2
        mkdir -p "$local_filestore_dir"

        echo ">> [fs] streaming tar of remote filestore '$remote_db' -> $local_filestore_dir ..." >&2
        # ControlPath=none: independent ssh (see the db stream note above).
        ssh -o ControlPath=none "$remote_host" '. ~/scripts/odoo.env; tar -C "$data_dir/filestore" -zc "$odoo_db"' \
            | "$pv" \
            | tar -C "$local_filestore_dir" -zx
        local rc=("${PIPESTATUS[@]}")
        if [ "${rc[0]}" -ne 0 ] || [ "${rc[2]:-0}" -ne 0 ]; then
            echo ">> [fs] ERROR: remote tar/ssh or local extract failed (ssh=${rc[0]}, tar=${rc[2]:-?})." >&2
            return 1
        fi

        if [ "$remote_db" != "$local_db" ]; then
            echo ">> [fs] renaming extracted '$remote_db' -> '$local_db' ..." >&2
            [ -d "$local_filestore_target" ] && rm -rf "$local_filestore_target"
            mv "$local_filestore_dir/$remote_db" "$local_filestore_target"
        fi
        echo ">> [fs] done." >&2
    }

    # Run both in parallel; collect exit codes.
    local db_pid="" fs_pid="" db_rc=0 fs_rc=0
    if [ "$do_db" = 1 ]; then stream_db & db_pid=$!; fi
    if [ "$do_fs" = 1 ]; then stream_filestore & fs_pid=$!; fi
    if [ -n "$db_pid" ]; then wait "$db_pid" || db_rc=$?; fi
    if [ -n "$fs_pid" ]; then wait "$fs_pid" || fs_rc=$?; fi

    [ "$db_rc" -ne 0 ] && echo "Error: database stream failed (rc=$db_rc)" >&2
    [ "$fs_rc" -ne 0 ] && echo "Error: filestore stream failed (rc=$fs_rc)" >&2
    if [ "$db_rc" -ne 0 ] || [ "$fs_rc" -ne 0 ]; then
        echo "Error: one or more streams failed; local Odoo left stopped." >&2
        return 1
    fi

    if [ "$neutralize" = 1 ]; then
        neutralize_db || echo "Warning: neutralize step reported errors." >&2
    fi

    if [ "$no_start" = 1 ]; then
        echo "Done (Odoo not started; --no-start given)."
    else
        echo ">> Starting local Odoo..." >&2
        start_odoo
        echo "Done."
    fi
}

# Scaffold a new project: write odoo-<name>.conf for the chosen Odoo version
# (with optional enterprise + a list of modules), activate it, create the
# database, and install the requested modules. Usage:
#   new NAME [--version 18|19] [--enterprise] [--modules a,b,c]
#            [--db NAME] [--http-port N] [--no-start] [--force]
new_project() {
    local name="" version="18" enterprise=0 modules="" http_port="8069" no_start=0 force=0 repo=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --version)    version="$2"; shift ;;
            --enterprise) enterprise=1 ;;
            --modules)    modules="$2"; shift ;;
            --http-port)  http_port="$2"; shift ;;
            --repo)       repo="$2"; shift ;;
            --no-start)   no_start=1 ;;
            --force)      force=1 ;;
            -*)           echo "Error: unknown option '$1'" >&2; return 1 ;;
            *)            if [ -z "$name" ]; then name="$1"; else echo "Error: unexpected argument '$1'" >&2; return 1; fi ;;
        esac
        shift
    done

    if [ -z "$name" ]; then
        echo "Error: project name required"
        echo "Usage: $0 new NAME [--version 18|19] [--enterprise] [--modules a,b,c] [--repo PATH] [--http-port N] [--no-start]"
        return 1
    fi
    if [ "$version" != "18" ] && [ "$version" != "19" ]; then
        echo "Error: --version must be 18 or 19"; return 1
    fi

    local conf="odoo-${name}.conf"
    if [ -f "$conf" ] && [ "$force" != "1" ]; then
        echo "Error: $conf already exists (use --force to overwrite)"; return 1
    fi

    local src ent
    if [ "$version" = "19" ]; then src="_odoo19"; ent="_enterprise19"; else src="_odoo18"; ent="_enterprise18"; fi

    local apath="./${src}/addons"
    [ "$enterprise" = "1" ] && apath="${apath},./${ent}"
    apath="${apath},./${name}"

    # Custom-addons dir: keep the convention that ~/odoo/<name> is a SYMLINK to
    # the project's repo (default ~/git/<name>, or --repo PATH). Create it now so
    # the addons_path entry is valid from the start.
    if [ ! -L "$name" ] && [ ! -e "$name" ]; then
        local target="${repo:-$HOME/git/$name}"
        if [ ! -e "$target" ]; then
            mkdir -p "$target"
            echo "Created new addons repo $target (git init it when ready)."
        fi
        ln -s "$target" "$name"
        echo "Linked ./$name -> $target"
    fi

    echo "Writing $conf (Odoo $version$([ "$enterprise" = "1" ] && echo ', enterprise'))..."
    {
        echo "[options]"
        echo "; -- Version selection (read by manage_odoo.sh) --"
        if [ "$version" = "19" ]; then
            echo "; odoo_src = _odoo19"
            echo "; python_venv = _venv19"
        else
            echo "; (Odoo 18 — defaults _odoo18 / _venv18)"
        fi
        echo "; Modules this project needs (installed by 'odoo new'):"
        echo "; install_modules = ${modules}"
        echo ""
        echo "admin_passwd = admin"
        echo "db_name = ${name}"
        echo "db_host = localhost"
        echo "db_port = 5432"
        echo "db_user = odoo"
        echo "db_password ="
        echo "http_port = ${http_port}"
        echo "addons_path = ${apath}"
        echo "data_dir = ./_data"
        echo "filestore = ./_data/filestore"
        echo ""
        echo "unaccent = True"
        echo "list_db = False"
        echo "proxy_mode = True"
        echo ""
        echo "log_level = info"
    } > "$conf"

    # Activate the new config (back up the current one, like switch_config)
    [ -f odoo.conf ] && cp odoo.conf odoo.conf.prev
    cp "$conf" odoo.conf
    echo "Activated project '$name'."

    # Create the database and install the requested modules (reuses the fresh path)
    local -a fresh_args=()
    [ -n "$modules" ] && fresh_args+=(--init "$modules")
    [ "$no_start" = "1" ] && fresh_args+=(--no-start)
    create_fresh_db "${fresh_args[@]}"
}

# Display help
show_help() {
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo
    echo "Commands:"
    echo "  start                Start Odoo server if not already running"
    echo "  restart              Stop and restart Odoo server"
    echo "  stop                 Stop running Odoo server"
    echo "  status               Check if Odoo server is running"
    echo "  shell                Start interactive Odoo shell"
    echo "  upgrade MODULE[,...] [--error-only]  Upgrade specified module(s) and restart Odoo"
    echo "  update MODULE[,...] [--error-only]   Alias for upgrade"
    echo "  install MODULE[,...] [--error-only] Install specified module(s)"
    echo "  test [MODULE[,...]] [TAGS] [--error-only]  Run tests for specified modules or all tests"
    echo "  list_config          List available configurations"
    echo "  switch_config PROJECT  Stop Odoo, switch configuration, and restart"
    echo "  switch PROJECT         Alias for switch_config"
    echo "  import FILE [--db-only] [--neutralize] [--no-start]  Import a backup into the active project, then restart"
    echo "  import_backup FILE   Alias for import"
    echo "  fresh [--init MODULES] [--no-start]  Drop the DB+filestore and create a fresh DB (base + MODULES), then restart"
    echo "  create_fresh_db      Alias for fresh"
    echo "  stream HOST [--remote-db N] [--remote-data-dir P] [--db-only|--filestore-only] [--neutralize] [--no-start] [--yes]"
    echo "                       Stream a remote nellika.sh/tcff Odoo db+filestore (over SSH) into the active project, then restart"
    echo "  new NAME [--version 18|19] [--enterprise] [--modules a,b,c] [--repo PATH] [--http-port N] [--no-start]"
    echo "                       Scaffold odoo-NAME.conf (db=NAME, addons symlink ./NAME), activate, create DB, install modules"
    echo
    echo "Options:"
    echo "  --error-only         Show only error output (suppresses warning messages)"
    echo "  --db-only            (import) restore database only, skip filestore"
    echo "  --neutralize         (import) neutralize the DB after restore (disable mail/crons/payments)"
    echo "  --no-start           (import) do not start Odoo after the import"
    echo
    echo "Examples:"
    echo "  $0 start                          # Start Odoo server"
    echo "  $0 shell                          # Start interactive Odoo shell"
    echo "  $0 upgrade purchase_dual_unit     # Upgrade a single module (warnings + errors)"
    echo "  $0 update nell_thai_qr_pos        # Upgrade module (alias for upgrade)"
    echo "  $0 upgrade purchase_dual_unit --error-only  # Upgrade with error-only output"
    echo "  $0 upgrade sale,purchase          # Upgrade multiple modules"
    echo "  $0 install stock_account          # Install a single module (warnings + errors)"
    echo "  $0 test                           # Run all tests (warnings + errors)"
    echo "  $0 test purchase_dual_unit        # Run tests for specific module"
    echo "  $0 test purchase_dual_unit '' --error-only  # Run tests with error-only output"
    echo "  $0 test '' at_install            # Run only at_install tests"
    echo "  $0 list_config                    # List available configurations"
    echo "  $0 switch_config tora             # Switch to tora configuration"
    echo "  $0 import backup.zip              # Import an Odoo/odoo.sh zip and restart"
    echo "  $0 import backup.zip --db-only    # Restore database only (skip filestore)"
    echo "  $0 import prod.zip --neutralize   # Import then neutralize (safe dev copy)"
    echo "  $0 import dump.sql.gz             # Restore a gzipped SQL dump (db only)"
    echo "  $0 fresh                          # Reset to a fresh database (initialized with base)"
    echo "  $0 fresh --init base,sale         # Fresh database initialized with base+sale"
    echo "  $0 new acme --version 19 --enterprise --modules sale,account,stock"
    echo "                                    # New 19+enterprise project 'acme' with those modules"
}

# Main script
case "$1" in
    "start")
        if check_odoo; then
            echo "Odoo is already running"
        else
            start_odoo
        fi
        ;;
    "restart")
        kill_odoo
        start_odoo
        ;;
    "upgrade"|"update"|"frontend")
        if [ -z "$2" ]; then
            echo "Error: No modules specified for upgrade"
            echo "Usage: $0 upgrade MODULE[,...] [--error-only]"
            exit 1
        fi
        upgrade_modules "$2" "$3"
        ;;
    "install")
        if [ -z "$2" ]; then
            echo "Error: No modules specified for installation"
            echo "Usage: $0 install MODULE[,...] [--error-only]"
            exit 1
        fi
        install_modules "$2" "$3"
        ;;
    "test")
        # $2 = modules (optional), $3 = test tags (optional), $4 = --error-only flag (optional)
        # Handle different parameter combinations
        if [ "$2" = "--error-only" ]; then
            # test --error-only
            run_tests "" "" "--error-only"
        elif [ "$3" = "--error-only" ]; then
            # test MODULE --error-only
            run_tests "$2" "" "--error-only"
        elif [ "$4" = "--error-only" ]; then
            # test MODULE TAGS --error-only
            run_tests "$2" "$3" "--error-only"
        else
            # Normal operation
            run_tests "$2" "$3" ""
        fi
        ;;
    "stop")
        kill_odoo
        rm -f odoo.pid
        ;;
    "status")
        check_odoo
        ;;
    "shell")
        start_shell
        ;;
    "list_config")
        list_config
        ;;
    "switch_config"|"switch")
        if [ -z "$2" ]; then
            echo "Error: No project name specified"
            echo "Usage: $0 switch_config PROJECT_NAME"
            echo
            echo "Available configurations:"
            find . -maxdepth 1 -name "*.conf" -not -name "odoo.conf" | sed 's|./||' | sed 's|\.conf$||' | sort
            exit 1
        fi
        switch_config "$2"
        ;;
    "import_backup"|"import")
        shift
        import_backup "$@"
        ;;
    "create_fresh_db"|"fresh")
        shift
        create_fresh_db "$@"
        ;;
    "stream")
        shift
        stream_remote_odoo "$@"
        ;;
    "new")
        shift
        new_project "$@"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
