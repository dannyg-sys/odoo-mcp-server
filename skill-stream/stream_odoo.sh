#!/bin/bash
#
# odoo-stream — thin wrapper around the engine's `stream` verb. The actual
# implementation lives ONCE in scripts/manage_odoo.sh (stream_remote_odoo) and is
# shared with the `odoo` CLI and the MCP server. This script just forwards its
# arguments so a human can run the skill directly in a terminal (and still get
# the confirmation prompt; pass --yes to skip it).
#
# The same capability is available as:  odoo stream <host> [options]
# and via MCP:  odoo_project action=stream remoteHost=<host> ...
#
# Run with -h for the option list.
exec "__ENGINE__" stream "$@"
