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

# Read odoo source dir from active conf (marker: "; odoo_src = ..."), default "odoo"
get_odoo_src() {
    local src
    src=$(grep -E "^;[[:space:]]*odoo_src[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    echo "${src:-odoo}"
}

# Read python venv dir from active conf (marker: "; python_venv = ..."), default "venv"
get_python_venv() {
    local v
    v=$(grep -E "^;[[:space:]]*python_venv[[:space:]]*=" odoo.conf 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' ')
    echo "${v:-venv}"
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

# Create a FRESH (empty) database for the ACTIVE project: drop the existing
# database and its filestore, then create an empty database. Starting Odoo
# afterwards initializes it with the base modules. Flags: --init <modules> to
# install/initialize specific modules right away, --no-start to skip the restart.
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
    echo "Fresh database created."

    if [ -n "$init_modules" ]; then
        echo "Initializing modules: $init_modules"
        install_modules "$init_modules"
    fi

    if [ "$no_start" = "1" ]; then
        echo "Done (Odoo not started; --no-start given)."
    else
        echo "Starting Odoo (an empty database initializes base on startup)..."
        start_odoo
    fi
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
    echo "  fresh [--init MODULES] [--no-start]  Drop the DB+filestore and create an empty database, then restart"
    echo "  create_fresh_db      Alias for fresh"
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
    echo "  $0 fresh                          # Empty database (base auto-installs on start)"
    echo "  $0 fresh --init base,sale         # Empty database, initialize base+sale"
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
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
