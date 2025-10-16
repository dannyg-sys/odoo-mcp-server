#!/bin/bash

# Odoo MCP Server Wrapper with Auto-Restart
# This script keeps the MCP server running even if it crashes

LOG_FILE="/tmp/odoo-mcp-server.log"
MAX_RESTARTS=5
RESTART_WINDOW=60  # seconds
SERVER_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/build/index.js"

# Track restarts
restart_count=0
restart_window_start=$(date +%s)

echo "[$(date)] Starting Odoo MCP Server wrapper" >> "$LOG_FILE"

while true; do
    current_time=$(date +%s)
    time_diff=$((current_time - restart_window_start))
    
    # Reset counter if we're outside the restart window
    if [ $time_diff -gt $RESTART_WINDOW ]; then
        restart_count=0
        restart_window_start=$current_time
    fi
    
    # Check if we've restarted too many times
    if [ $restart_count -ge $MAX_RESTARTS ]; then
        echo "[$(date)] ERROR: Server crashed $MAX_RESTARTS times in $RESTART_WINDOW seconds. Giving up." >> "$LOG_FILE"
        exit 1
    fi
    
    echo "[$(date)] Starting MCP server (restart #$restart_count)" >> "$LOG_FILE"
    
    # Run the server
    node "$SERVER_PATH" 2>> "$LOG_FILE"
    exit_code=$?
    
    echo "[$(date)] Server exited with code $exit_code" >> "$LOG_FILE"
    
    # If exit code is 0, it was a clean shutdown, don't restart
    if [ $exit_code -eq 0 ]; then
        echo "[$(date)] Clean shutdown, exiting wrapper" >> "$LOG_FILE"
        exit 0
    fi
    
    # Increment restart counter
    restart_count=$((restart_count + 1))
    
    # Wait a bit before restarting
    echo "[$(date)] Waiting 2 seconds before restart..." >> "$LOG_FILE"
    sleep 2
done
