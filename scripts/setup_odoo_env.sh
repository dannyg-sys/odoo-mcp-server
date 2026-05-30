#!/usr/bin/env bash
#
# Bootstrap a fresh Odoo development base (the layout the `odoo` tooling expects).
#
# Creates $ODOO_BASE (default ~/odoo) and, inside it, the _-prefixed system dirs:
#   _odoo18 / _odoo19          Odoo Community 18.0 / 19.0   (odoo/odoo.git)
#   _enterprise18 / _enterprise19  Odoo Enterprise 18.0 / 19.0  (odoo/enterprise.git, PRIVATE)
#   _venv18 / _venv19          per-version Python virtualenvs (+ pip install requirements)
#   _data                      filestore + sessions
#   _scripts / _concepts       helper-script and concept dirs (see CLAUDE.md/README.md)
# and seeds CLAUDE.md / README.md from the repo templates if absent.
#
# Requirements: git, python3 (3.10+), PostgreSQL (createdb/psql), and GitHub access
# to the PRIVATE odoo/enterprise repo (SSH key on your GitHub account, or a token).
#
# Idempotent: existing checkouts/venvs/dirs are detected and skipped.
#
# Usage:
#   ./setup_odoo_env.sh
#   ODOO_BASE=/path/to/base ./setup_odoo_env.sh     # different base dir
#   PYTHON=python3.11 ./setup_odoo_env.sh           # pick the interpreter
#   FULL_CLONE=1 ./setup_odoo_env.sh                # full history (default: --depth 1)
#   ENTERPRISE_REMOTE=https ./setup_odoo_env.sh     # HTTPS for enterprise (default: ssh)
#   SKIP_ENTERPRISE=1 ./setup_odoo_env.sh           # community only (no enterprise repos)

set -euo pipefail

ODOO_BASE="${ODOO_BASE:-$HOME/odoo}"
PYTHON="${PYTHON:-python3}"
FULL_CLONE="${FULL_CLONE:-0}"
ENTERPRISE_REMOTE="${ENTERPRISE_REMOTE:-ssh}"   # ssh | https
SKIP_ENTERPRISE="${SKIP_ENTERPRISE:-0}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # odoo-mcp-server root (templates/)

CE_URL="https://github.com/odoo/odoo.git"
if [ "$ENTERPRISE_REMOTE" = "https" ]; then
  EE_URL="https://github.com/odoo/enterprise.git"
else
  EE_URL="git@github.com:odoo/enterprise.git"
fi

DEPTH=(--depth 1 --single-branch)
[ "$FULL_CLONE" = "1" ] && DEPTH=()

say() { printf '\n=== %s ===\n' "$1"; }

# Hard requirements
for t in git "$PYTHON"; do
  command -v "$t" >/dev/null 2>&1 || { echo "Error: required tool not found: $t" >&2; exit 1; }
done
# Soft requirement (needed to actually run Odoo, not to bootstrap)
command -v createdb >/dev/null 2>&1 || echo "Warning: PostgreSQL 'createdb' not on PATH — install/start PostgreSQL before running Odoo."

say "Odoo base: $ODOO_BASE"
mkdir -p "$ODOO_BASE"
cd "$ODOO_BASE"

clone_src() {
  local dest="$1" url="$2" branch="$3"
  if [ -d "$dest/.git" ]; then echo "✓ $dest already a checkout — skipping"; return; fi
  echo "Cloning $url @ $branch -> $dest ..."
  git clone "${DEPTH[@]}" --branch "$branch" "$url" "$dest"
}

say "Cloning Odoo sources"
clone_src _odoo18 "$CE_URL" 18.0
clone_src _odoo19 "$CE_URL" 19.0
if [ "$SKIP_ENTERPRISE" = "1" ]; then
  echo "Skipping enterprise (SKIP_ENTERPRISE=1)."
else
  echo "Enterprise repos are PRIVATE — this needs GitHub access (remote: $ENTERPRISE_REMOTE)."
  clone_src _enterprise18 "$EE_URL" 18.0
  clone_src _enterprise19 "$EE_URL" 19.0
fi

make_venv() {
  local venv="$1" src="$2"
  if [ -x "$venv/bin/python3" ]; then echo "✓ $venv exists — skipping"; return; fi
  [ -d "$src" ] || { echo "Skip $venv: source $src not present"; return; }
  echo "Creating venv $venv (from $src/requirements.txt) ..."
  "$PYTHON" -m venv "$venv"
  "$venv/bin/python3" -m pip install --upgrade pip wheel
  [ -f "$src/requirements.txt" ] && "$venv/bin/python3" -m pip install -r "$src/requirements.txt"
}

say "Building virtualenvs"
make_venv _venv18 _odoo18
make_venv _venv19 _odoo19

say "Runtime directories"
mkdir -p _data/filestore _scripts _concepts
echo "✓ _data/ _scripts/ _concepts/"

say "Seeding base docs + sample config (templates, not overwritten)"
for f in CLAUDE README; do
  tmpl="$REPO_DIR/templates/${f}.odoo.md"
  if [ -f "$tmpl" ] && [ ! -f "$ODOO_BASE/${f}.md" ]; then
    cp "$tmpl" "$ODOO_BASE/${f}.md" && echo "seeded ${f}.md"
  else
    echo "✓ ${f}.md present or no template — leaving as-is"
  fi
done
if [ -f "$REPO_DIR/templates/odoo-sample.conf" ] && [ ! -f "$ODOO_BASE/odoo-sample.conf" ]; then
  cp "$REPO_DIR/templates/odoo-sample.conf" "$ODOO_BASE/odoo-sample.conf" && echo "seeded odoo-sample.conf"
else
  echo "✓ odoo-sample.conf present or no template — leaving as-is"
fi

say "Done"
echo "Base ready at $ODOO_BASE."
echo "Next steps:"
echo "  1. cp odoo-sample.conf odoo-<project>.conf and edit it (db_name, addons_path,"
echo "     and the ; odoo_src / ; python_venv markers for Odoo 19)."
echo "  2. odoo switch <project>   # activate it and start Odoo"
echo "  3. odoo import <backup>  or  odoo fresh   # load a database"
