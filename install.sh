#!/usr/bin/env bash
#
# Install the odoo tooling on this machine:
#   1. the `odoo-manage` Claude Code skill  -> ~/.claude/skills/odoo-manage/SKILL.md
#   2. the `odoo-stream` Claude Code skill  -> ~/.claude/skills/odoo-stream/{SKILL.md,stream_odoo.sh}
#   3. the `odoo` command (smart front door) -> ~/.local/bin/odoo  (symlink to build/cli.js)
#   4. the `manage_odoo` command (raw engine) -> ~/.local/bin/manage_odoo (symlink to scripts/manage_odoo.sh)
#
# The skill is rendered from skill/SKILL.md with the absolute path of *this*
# checkout, so it works no matter where the repo is cloned. The two commands are
# symlinks, so they always reflect the latest build/script.
#
# Usage:
#   ./install.sh            # build if needed, then install
#   ./install.sh --force    # also overwrite an existing skill file
#
# Env:
#   ODOO_BIN_DIR      where to put the command symlinks (default ~/.local/bin)
#   CLAUDE_SKILLS_DIR where to put the skill (default ~/.claude/skills)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skill/SKILL.md"
STREAM_SKILL_SRC="$REPO_DIR/skill-stream/SKILL.md"
STREAM_SH_SRC="$REPO_DIR/skill-stream/stream_odoo.sh"
CLI="$REPO_DIR/build/cli.js"
ENGINE="$REPO_DIR/scripts/manage_odoo.sh"

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST_DIR="$SKILLS_DIR/odoo-manage"
DEST="$DEST_DIR/SKILL.md"
STREAM_DEST_DIR="$SKILLS_DIR/odoo-stream"
STREAM_SH="$STREAM_DEST_DIR/stream_odoo.sh"
BIN_DIR="${ODOO_BIN_DIR:-$HOME/.local/bin}"

if [ ! -f "$SKILL_SRC" ]; then
  echo "Error: skill template not found at $SKILL_SRC" >&2
  exit 1
fi

# Build the CLI if it isn't there yet.
if [ ! -f "$CLI" ]; then
  echo "build/cli.js not found — building..."
  ( cd "$REPO_DIR" && npm install && npm run build )
fi

# --- 1. Skill -------------------------------------------------------------
if [ -e "$DEST" ] && [ "${1:-}" != "--force" ]; then
  echo "Skill already installed at $DEST (use --force to overwrite)."
else
  mkdir -p "$DEST_DIR"
  # Render the template, substituting the absolute paths for this checkout.
  # Use '|' as the sed delimiter since the values contain '/'.
  sed -e "s|__ODOO_CLI__|$CLI|g" \
      -e "s|__REPO_DIR__|$REPO_DIR|g" \
      "$SKILL_SRC" > "$DEST"
  echo "Installed skill -> $DEST"
fi

# --- 2. odoo-stream skill (SKILL.md + script) ----------------------------
# The script is rendered too (it carries an __ODOO_CLI__ default), and SKILL.md
# additionally references the installed script path via __STREAM_SH__.
if [ ! -f "$STREAM_SKILL_SRC" ] || [ ! -f "$STREAM_SH_SRC" ]; then
  echo "Note: odoo-stream sources not found at $REPO_DIR/skill-stream — skipping."
elif [ -e "$STREAM_SH" ] && [ "${1:-}" != "--force" ]; then
  echo "Skill already installed at $STREAM_DEST_DIR (use --force to overwrite)."
else
  mkdir -p "$STREAM_DEST_DIR"
  sed -e "s|__ODOO_CLI__|$CLI|g" \
      -e "s|__STREAM_SH__|$STREAM_SH|g" \
      "$STREAM_SKILL_SRC" > "$STREAM_DEST_DIR/SKILL.md"
  sed -e "s|__ODOO_CLI__|$CLI|g" \
      "$STREAM_SH_SRC" > "$STREAM_SH"
  chmod +x "$STREAM_SH"
  echo "Installed skill -> $STREAM_DEST_DIR/SKILL.md"
  echo "Installed script -> $STREAM_SH"
fi

# --- 3 & 4. Command symlinks ---------------------------------------------
mkdir -p "$BIN_DIR"
chmod +x "$CLI" "$ENGINE" 2>/dev/null || true
ln -sf "$CLI" "$BIN_DIR/odoo"
ln -sf "$ENGINE" "$BIN_DIR/manage_odoo"
echo "Installed command -> $BIN_DIR/odoo        (-> $CLI)"
echo "Installed command -> $BIN_DIR/manage_odoo (-> $ENGINE)"

# PATH check
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "WARNING: $BIN_DIR is not on your PATH — add it to use 'odoo' / 'manage_odoo'." ;;
esac

echo
echo "Done. Start a new Claude Code session to pick up the skill."
echo "Try: odoo status"
