#!/usr/bin/env bash
# ingest-omc.sh — pulls OMC state into project MEMORY.md
# Usage: ingest-omc.sh [PROJECT_ROOT]
#
# Sources (project-local):
#   <project>/.omc/state/mission-state.json     → ## Active Context
#   <project>/.omc/state/agent-replay-*.jsonl   → ## Session History (most recent)

set -euo pipefail
CONTENT_FILE=""
PM_CONTENT_FILE=""
trap 'rm -f "${CONTENT_FILE:-}" "${PM_CONTENT_FILE:-}" "${PM_CONTENT_FILE:-}.new"' EXIT

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
OMC_STATE="$PROJECT_ROOT/.omc/state"

[ -f "$MEMORY" ]    || exit 0
[ -d "$OMC_STATE" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "ax: jq required" >&2; exit 1; }

# shellcheck source=../lib/ax-utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/ax-utils.sh"

file_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then
    stat -f %m "$1"
  else
    stat -c %Y "$1"
  fi
}

date_from_epoch() {
  if date -u -r "$1" +%Y-%m-%d >/dev/null 2>&1; then
    date -u -r "$1" +%Y-%m-%d
  elif date -u -d "@$1" +%Y-%m-%d >/dev/null 2>&1; then
    date -u -d "@$1" +%Y-%m-%d
  else
    date -u +%Y-%m-%d
  fi
}

# ── Active Context from mission-state.json ────────────────────────────────────
MISSION_FILE="$OMC_STATE/mission-state.json"
if [ -f "$MISSION_FILE" ]; then
  UPDATED_AT=$(jq -r '.updatedAt // empty' "$MISSION_FILE" 2>/dev/null || true)
  [ -z "$UPDATED_AT" ] && UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  DATE=$(printf '%s' "$UPDATED_AT" | cut -c1-10)

  CONTENT_FILE=$(mktemp)
  printf '_Updated: %s_\n\n' "$DATE" > "$CONTENT_FILE"

  jq -r '
    .missions[] |
    "**\(.name)** (\(.status)) — \(.taskCounts.completed)/\(.taskCounts.total) tasks  \n" +
    "  Objective: \(.objective)  \n" +
    "  Agents: " + ([.agents[].role] | unique | join(", "))
  ' "$MISSION_FILE" 2>/dev/null >> "$CONTENT_FILE" || true

  if [ "$(wc -l < "$CONTENT_FILE")" -le 2 ]; then
    printf '_No active missions._\n' >> "$CONTENT_FILE"
  fi

  ax_replace_section "$MEMORY" "active-context" "$CONTENT_FILE"
  rm -f "$CONTENT_FILE"
fi

# ── Session History from most recent agent-replay-*.jsonl ────────────────────
REPLAY_FILE=$(ls -t "$OMC_STATE"/agent-replay-*.jsonl 2>/dev/null | head -1 || true)

if [ -n "$REPLAY_FILE" ]; then
  SESSION_ID=$(basename "$REPLAY_FILE" .jsonl | sed 's/^agent-replay-//')
  ENTRY_ID="${SESSION_ID:0:12}-omc"

  # Skip if already ingested
  if ! grep -qF "entry:${ENTRY_ID}" "$MEMORY" 2>/dev/null; then
    AGENT_TYPES=$(jq -r 'select(.event == "agent_start") | .agent_type' "$REPLAY_FILE" 2>/dev/null \
      | sort -u | tr '\n' ',' | sed 's/,$//')
    SUCCEEDED=$(jq -r 'select(.event == "agent_stop" and .success == true) | .agent_type' \
      "$REPLAY_FILE" 2>/dev/null | wc -l | tr -d ' ')
    FAILED=$(jq -r 'select(.event == "agent_stop" and .success == false) | .agent_type' \
      "$REPLAY_FILE" 2>/dev/null | wc -l | tr -d ' ')

    FILE_DATE=$(date_from_epoch "$(file_mtime "$REPLAY_FILE" 2>/dev/null || echo 0)")

    STATUS_TAG=""
    [ "$FAILED" -gt 0 ] && STATUS_TAG=" (${FAILED} failed)"

    CONTENT_FILE=$(mktemp)
    # Prepend the new entry, keep existing history below
    ax_get_section "$MEMORY" "session-history" \
      | grep -v '^_No sessions recorded yet' > "$CONTENT_FILE" || true

    {
      printf '<!-- entry:%s -->\n' "$ENTRY_ID"
      printf '%s\n' "- **${FILE_DATE}** OMC \`${SESSION_ID:0:8}\` — ${SUCCEEDED} agents (${AGENT_TYPES})${STATUS_TAG}"
      cat "$CONTENT_FILE"
    } > "${CONTENT_FILE}.new" && mv "${CONTENT_FILE}.new" "$CONTENT_FILE"

    if [ ! -s "$CONTENT_FILE" ]; then
      printf '_No sessions recorded yet.\n' > "$CONTENT_FILE"
    fi

    ax_replace_section "$MEMORY" "session-history" "$CONTENT_FILE"
    rm -f "$CONTENT_FILE"
  fi
fi

# ── Project Memory from .omc/project-memory.json ─────────────────────────────
PROJECT_MEMORY_FILE="$PROJECT_ROOT/.omc/project-memory.json"
DECISIONS_FILE="$PROJECT_ROOT/.ax/memory/decisions.md"

if [ -f "$PROJECT_MEMORY_FILE" ] && [ -f "$DECISIONS_FILE" ] && command -v jq >/dev/null 2>&1; then
  ENTRIES=$(jq -r '
    (.entries // [])
    | sort_by(.createdAt) | reverse | .[0:10]
    | .[]
    | [.id, .createdAt[:10], .content] | @tsv
  ' "$PROJECT_MEMORY_FILE" 2>/dev/null || true)

  if [ -n "$ENTRIES" ]; then
    PM_CONTENT_FILE=$(mktemp)

    ax_get_section "$DECISIONS_FILE" "decisions" \
      | grep -v '^_No decisions recorded yet' > "$PM_CONTENT_FILE" || true

    ADDED=0
    while IFS=$'\t' read -r ENTRY_ID ENTRY_DATE ENTRY_CONTENT; do
      [ -n "$ENTRY_ID" ] || continue
      SHORT_ID="${ENTRY_ID:0:8}"
      DEDUP_ID="omc-${SHORT_ID}"

      grep -qF "entry:${DEDUP_ID}" "$DECISIONS_FILE" 2>/dev/null && continue

      {
        printf '<!-- entry:%s -->\n' "$DEDUP_ID"
        printf '**%s** (omc): %s\n\n' "$ENTRY_DATE" "$ENTRY_CONTENT"
        cat "$PM_CONTENT_FILE"
      } > "${PM_CONTENT_FILE}.new" && mv "${PM_CONTENT_FILE}.new" "$PM_CONTENT_FILE"
      ADDED=$((ADDED + 1))
    done <<< "$ENTRIES"

    if [ "$ADDED" -gt 0 ]; then
      ax_replace_section "$DECISIONS_FILE" "decisions" "$PM_CONTENT_FILE"
    fi
    rm -f "$PM_CONTENT_FILE"
  fi
fi
