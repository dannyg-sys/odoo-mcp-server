#!/usr/bin/env bash
#
# Install the odoo-manage Claude Code skill into ~/.claude/skills.
#
# The skill drives this repo's CLI (build/cli.js). Because the repo may be
# cloned to different paths on different machines, this script renders the
# skill template (skill/SKILL.md) with the absolute path of *this* checkout,
# so the installed skill always points at the right cli.js.
#
# Usage:
#   ./install-skill.sh            # build if needed, then install
#   ./install-skill.sh --force    # reinstall even if already present

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skill/SKILL.md"
CLI="$REPO_DIR/build/cli.js"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST_DIR="$SKILLS_DIR/odoo-manage"
DEST="$DEST_DIR/SKILL.md"

if [ ! -f "$SKILL_SRC" ]; then
  echo "Error: skill template not found at $SKILL_SRC" >&2
  exit 1
fi

# Build the CLI if it isn't there yet.
if [ ! -f "$CLI" ]; then
  echo "build/cli.js not found — building..."
  ( cd "$REPO_DIR" && npm install && npm run build )
fi

if [ -e "$DEST" ] && [ "${1:-}" != "--force" ]; then
  echo "Skill already installed at $DEST (use --force to overwrite)."
  exit 0
fi

mkdir -p "$DEST_DIR"

# Render the template, substituting the absolute paths for this checkout.
# Use '|' as the sed delimiter since the values contain '/'.
sed -e "s|__ODOO_CLI__|$CLI|g" \
    -e "s|__REPO_DIR__|$REPO_DIR|g" \
    "$SKILL_SRC" > "$DEST"

echo "Installed odoo-manage skill:"
echo "  source: $SKILL_SRC"
echo "  -> $DEST"
echo "  cli:    $CLI"
echo
echo "Start a new Claude Code session to pick it up."
