#!/usr/bin/env bash
# ingest-gstack.sh — pulls gstack analytics into project MEMORY.md
# Usage: ingest-gstack.sh [PROJECT_ROOT]
#
# Sources:
#   ~/.gstack/analytics/eureka.jsonl      → ## Decisions & Rationale
#   ~/.gstack/analytics/skill-usage.jsonl → ## Session History (last 10)

set -euo pipefail
CONTENT_FILE=""
trap 'rm -f "${CONTENT_FILE:-}"' EXIT

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"

[ -f "$MEMORY" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "ax: jq required" >&2; exit 1; }

# shellcheck source=../lib/ax-utils.sh
source "$HOME/.ax/lib/ax-utils.sh"

# ── Decisions & Rationale from eureka.jsonl ──────────────────────────────────
# eureka.jsonl may be pretty-printed — use jq -c to emit one object per line
EUREKA="$HOME/.gstack/analytics/eureka.jsonl"
if [ -f "$EUREKA" ]; then
  mapfile -t EXISTING_IDS < <(ax_get_entry_ids "$MEMORY" "decisions")

  CONTENT_FILE=$(mktemp)
  ax_get_section "$MEMORY" "decisions" \
    | grep -v '^_No decisions recorded yet' > "$CONTENT_FILE" || true

  NEW_COUNT=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TS=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null || true)
    INSIGHT=$(printf '%s' "$line" | jq -r '.insight // empty' 2>/dev/null || true)
    SKILL=$(printf '%s' "$line" | jq -r '.skill // "unknown"' 2>/dev/null || true)
    [ -z "$TS" ] || [ -z "$INSIGHT" ] && continue

    ENTRY_ID="$(printf '%s' "$TS" | tr -cd '0-9' | cut -c1-12)-eureka"
    printf '%s\n' "${EXISTING_IDS[@]+"${EXISTING_IDS[@]}"}" | grep -qF "$ENTRY_ID" && continue

    DATE=$(printf '%s' "$TS" | cut -c1-10)
    {
      printf '<!-- entry:%s -->\n' "$ENTRY_ID"
      printf '**%s** (`%s`): %s\n\n' "$DATE" "$SKILL" "$INSIGHT"
    } >> "$CONTENT_FILE"
    NEW_COUNT=$((NEW_COUNT + 1))
  done < <(jq -c '.' "$EUREKA" 2>/dev/null)

  if [ "$NEW_COUNT" -gt 0 ] || [ -s "$CONTENT_FILE" ]; then
    if [ ! -s "$CONTENT_FILE" ]; then
      printf '_No decisions recorded yet.\n' > "$CONTENT_FILE"
    fi
    ax_replace_section "$MEMORY" "decisions" "$CONTENT_FILE"
  fi
  rm -f "$CONTENT_FILE"
fi

# ── Session History from skill-usage.jsonl (last 10) ─────────────────────────
USAGE="$HOME/.gstack/analytics/skill-usage.jsonl"
if [ -f "$USAGE" ]; then
  mapfile -t EXISTING_IDS < <(ax_get_entry_ids "$MEMORY" "session-history")

  CONTENT_FILE=$(mktemp)
  ax_get_section "$MEMORY" "session-history" \
    | grep -v '^_No sessions recorded yet' > "$CONTENT_FILE" || true

  NEW_COUNT=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TS=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null || true)
    SKILL=$(printf '%s' "$line" | jq -r '.skill // empty' 2>/dev/null || true)
    [ -z "$TS" ] || [ -z "$SKILL" ] && continue

    ENTRY_ID="$(printf '%s' "$TS" | tr -cd '0-9' | cut -c1-12)-skill"
    printf '%s\n' "${EXISTING_IDS[@]+"${EXISTING_IDS[@]}"}" | grep -qF "$ENTRY_ID" && continue

    OUTCOME=$(printf '%s' "$line" | jq -r '.outcome // "-"' 2>/dev/null || true)
    REPO=$(printf '%s' "$line" | jq -r '.repo // ""' 2>/dev/null || true)
    DUR=$(printf '%s' "$line" | jq -r '.duration_s // ""' 2>/dev/null || true)
    DATE=$(printf '%s' "$TS" | cut -c1-10)

    DETAIL=""
    [ -n "$REPO" ] && DETAIL=" @ ${REPO}"
    [ -n "$DUR" ] && DETAIL="${DETAIL} (${DUR}s)"

    {
      printf '<!-- entry:%s -->\n' "$ENTRY_ID"
      # Use printf -- to prevent leading '-' in format from being parsed as option
      printf -- '- **%s** `/%s`%s: %s\n' "$DATE" "$SKILL" "$DETAIL" "$OUTCOME"
    } >> "$CONTENT_FILE"
    NEW_COUNT=$((NEW_COUNT + 1))
  done < <(tail -15 "$USAGE")

  if [ "$NEW_COUNT" -gt 0 ] || [ -s "$CONTENT_FILE" ]; then
    if [ ! -s "$CONTENT_FILE" ]; then
      printf '_No sessions recorded yet.\n' > "$CONTENT_FILE"
    fi
    ax_replace_section "$MEMORY" "session-history" "$CONTENT_FILE"
  fi
  rm -f "$CONTENT_FILE"
fi
