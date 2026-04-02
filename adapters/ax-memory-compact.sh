#!/usr/bin/env bash
# ax-memory-compact.sh — Rolling Summary + Hard Cap compaction for topic files
# Usage: ax-memory-compact.sh [PROJECT_ROOT]
# Called by ax-ingest.sh after all adapters run.
#
# For each topic file, if entry count > AX_COMPACT_HARD_CAP:
#   - Keeps newest AX_COMPACT_KEEP_RECENT entries verbatim
#   - Replaces older entries with one compact notice entry
#
# Env overrides:
#   AX_COMPACT_HARD_CAP      (default: 20)
#   AX_COMPACT_KEEP_RECENT   (default: 15)

set -euo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AX_COMPACT_HARD_CAP="${AX_COMPACT_HARD_CAP:-20}"
AX_COMPACT_KEEP_RECENT="${AX_COMPACT_KEEP_RECENT:-15}"

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/.." && pwd)"

# shellcheck source=../lib/ax-utils.sh
source "$PLUGIN_ROOT/lib/ax-utils.sh"

command -v python3 >/dev/null 2>&1 || { echo "ax-compact: python3 not found, skipping" >&2; exit 0; }
[ -f "$PLUGIN_ROOT/bin/ax-compact.py" ] || { echo "ax-compact: ax-compact.py not found, skipping" >&2; exit 0; }

# topic-file-name:section-name pairs to check
TOPIC_SECTIONS=(
  "decisions:decisions"
  "research-notes:research-notes"
  "experiment-log:experiment-log"
  "study-notes:study-notes"
)

for _PAIR in "${TOPIC_SECTIONS[@]}"; do
  _TOPIC="${_PAIR%%:*}"
  _SECTION="${_PAIR##*:}"
  _TOPIC_FILE="$PROJECT_ROOT/.ax/memory/${_TOPIC}.md"

  [ -f "$_TOPIC_FILE" ] || continue

  _TMPOUT=$(python3 "$PLUGIN_ROOT/bin/ax-compact.py" \
    "$_TOPIC_FILE" "$_SECTION" "$AX_COMPACT_HARD_CAP" "$AX_COMPACT_KEEP_RECENT" \
    2>/dev/null) || true

  if [ -n "$_TMPOUT" ] && [ -f "$_TMPOUT" ]; then
    ax_replace_section "$_TOPIC_FILE" "$_SECTION" "$_TMPOUT"
    rm -f "$_TMPOUT"
    printf 'ax-compact: compacted %s/%s\n' "$_TOPIC" "$_SECTION" >&2
  fi
done
