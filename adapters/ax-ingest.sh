#!/usr/bin/env bash
# ax-ingest.sh — SessionEnd hook orchestrator
# Reads project root from Claude hook stdin (cwd field), then runs adapters under flock.

set -euo pipefail

# Read stdin JSON from Claude hook (non-blocking)
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat 2>/dev/null || true)
fi

# Resolve PROJECT_ROOT: stdin cwd → git root → pwd
PROJECT_ROOT=""
if [ -n "$STDIN_DATA" ] && command -v jq >/dev/null 2>&1; then
  PROJECT_ROOT=$(printf '%s' "$STDIN_DATA" | jq -r '.cwd // empty' 2>/dev/null || true)
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

# Only run if this project has been ax-initialized
[ -d "$PROJECT_ROOT/.ax" ] || exit 0

LOCAL_MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/.." && pwd)"

# Bootstrap MEMORY.md from template on first run
if [ ! -f "$LOCAL_MEMORY" ]; then
  TEMPLATE="$PLUGIN_ROOT/templates/MEMORY.template.md"
  [ -f "$TEMPLATE" ] || exit 0
  mkdir -p "$(dirname "$LOCAL_MEMORY")"
  SLUG=$(basename "$PROJECT_ROOT")
  SLUG_ESCAPED=$(printf '%s' "$SLUG" | sed 's/[&\]/\\&/g')
  sed "s/{{project_slug}}/$SLUG_ESCAPED/g" "$TEMPLATE" > "$LOCAL_MEMORY"
fi

LOCKFILE="$PROJECT_ROOT/.ax/.ingest.lock"
mkdir -p "$(dirname "$LOCKFILE")"

(
  flock -n 9 || exit 0
  "$ADAPTER_DIR/ingest-gstack.sh"   "$PROJECT_ROOT"
  "$ADAPTER_DIR/ingest-omc.sh"      "$PROJECT_ROOT"
  "$ADAPTER_DIR/ingest-research.sh" "$PROJECT_ROOT"
) 9>"$LOCKFILE"
