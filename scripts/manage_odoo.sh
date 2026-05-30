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

# Function to import Odoo backup
import_backup() {
    local backup_file="$1"
    
    # Check if backup file was provided
    if [ -z "$backup_file" ]; then
        echo "Error: No backup file specified"
        echo "Usage: $0 import_backup <backup.zip>"
        return 1
    fi
    
    # Check if backup file exists
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file '$backup_file' not found"
        return 1
    fi
    
    # Extract settings from odoo.conf
    local db_name=$(grep "^db_name" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local db_user=$(grep "^db_user" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    local filestore_dir=$(grep "^filestore" odoo.conf | cut -d'=' -f2 | tr -d ' ')
    
    echo "Importing Odoo backup with the following settings:"
    echo "Database: $db_name"
    echo "Filestore: $filestore_dir"
    echo "Backup file: $backup_file"
    
    # Stop Odoo if running
    if check_odoo > /dev/null 2>&1; then
        echo "Stopping Odoo..."
        kill_odoo
        rm -f odoo.pid
    fi
    
    # Create temporary directory
    local tmp_dir=$(mktemp -d)
    echo "Created temporary directory: $tmp_dir"
    
    # Unzip backup file
    echo "Extracting backup file..."
    unzip -q "$backup_file" -d "$tmp_dir" || { echo "Failed to extract backup file"; rm -rf "$tmp_dir"; return 1; }
    
    # Check if necessary files exist
    if [ ! -f "$tmp_dir/dump.sql" ]; then
        echo "Error: SQL dump file not found in backup"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    if [ ! -d "$tmp_dir/filestore" ]; then
        echo "Warning: Filestore directory not found in backup"
    fi
    
    # Drop existing database if it exists
    echo "Dropping existing database $db_name if it exists..."
    dropdb -U "$db_user" "$db_name" 2>/dev/null
    
    # Create fresh database
    echo "Creating new database $db_name..."
    createdb -U "$db_user" "$db_name" || { echo "Failed to create database"; rm -rf "$tmp_dir"; return 1; }
    
    # Import SQL dump
    echo "Importing database dump..."
    psql -U "$db_user" -d "$db_name" < "$tmp_dir/dump.sql" > /dev/null || { echo "Failed to import database"; rm -rf "$tmp_dir"; return 1; }
    
    # Handle filestore
    if [ -d "$tmp_dir/filestore" ]; then
        echo "Moving filestore to $filestore_dir/$db_name..."
        
        # Remove existing filestore if it exists
        if [ -d "$filestore_dir/$db_name" ]; then
            echo "Removing existing filestore..."
            rm -rf "$filestore_dir/$db_name"
        fi
        
        # Ensure parent directory exists
        mkdir -p "$filestore_dir"
        
        # Move filestore to proper location
        mv "$tmp_dir/filestore" "$filestore_dir/$db_name" || { echo "Failed to move filestore"; rm -rf "$tmp_dir"; return 1; }
    fi
    
    # Clean up
    echo "Cleaning up temporary files..."
    rm -rf "$tmp_dir"
    
    echo "Import completed successfully!"
    echo "Starting Odoo with imported database..."
    start_odoo
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
    echo "  import_backup FILE   Stop Odoo, import backup, and restart"
    echo
    echo "Options:"
    echo "  --error-only         Show only error output (suppresses warning messages)"
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
    echo "  $0 import_backup backup.zip       # Import backup and restart Odoo"
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
    "import_backup")
        if [ -z "$2" ]; then
            echo "Error: No backup file specified"
            echo "Usage: $0 import_backup <backup.zip>"
            exit 1
        fi
        import_backup "$2"
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
