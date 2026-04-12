#!/usr/bin/env bash
# ingest-routing.sh — called by ax-ingest.sh at SessionEnd
# Runs ax-learn.py if routing-log.jsonl exists, generating routing-suggestions.md

set -euo pipefail

PROJECT_ROOT="${1:-}"
[ -n "$PROJECT_ROOT" ] || exit 0
[ -d "$PROJECT_ROOT/.ax" ] || exit 0

LOG_FILE="$PROJECT_ROOT/.ax/routing-log.jsonl"
[ -f "$LOG_FILE" ] || exit 0

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/.." && pwd)"

LEARN_BIN="$PLUGIN_ROOT/bin/ax-learn.py"
[ -f "$LEARN_BIN" ] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

python3 "$LEARN_BIN" "$LOG_FILE" "$PLUGIN_ROOT/routing/skill-routing.yaml" "$PROJECT_ROOT/.ax/memory/routing-suggestions.md" 2>/dev/null || true
