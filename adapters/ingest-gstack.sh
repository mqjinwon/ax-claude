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
PROJECT_ROOT_REAL="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P || printf '%s\n' "$PROJECT_ROOT")"
PROJECT_NAME="$(basename "$PROJECT_ROOT_REAL")"

[ -f "$MEMORY" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "ax: jq required" >&2; exit 1; }

# shellcheck source=../lib/ax-utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/ax-utils.sh"

repo_matches_project() {
  local repo_path candidate candidate_base
  repo_path="${1:-}"
  [ -n "$repo_path" ] || return 1

  candidate="${repo_path%/}"
  [ "$candidate" = "$PROJECT_ROOT" ] && return 0
  [ "$candidate" = "$PROJECT_ROOT_REAL" ] && return 0

  case "$candidate" in
    */*)
      return 1
      ;;
  esac

  candidate_base="$(basename "$candidate")"
  candidate_base="${candidate_base%.git}"
  [ "$candidate_base" = "$PROJECT_NAME" ]
}

# ── Decisions & Rationale from eureka.jsonl ──────────────────────────────────
# eureka.jsonl may be pretty-printed — use jq -c to emit one object per line
EUREKA="$HOME/.gstack/analytics/eureka.jsonl"
if [ -f "$EUREKA" ]; then
  # v1.4+: split memory — write to decisions.md if it exists, else MEMORY.md
  DECISIONS_TARGET="$PROJECT_ROOT/.ax/memory/decisions.md"
  if [ ! -f "$DECISIONS_TARGET" ]; then
    DECISIONS_TARGET="$MEMORY"
  fi

  CONTENT_FILE=$(mktemp)
  ax_get_section "$DECISIONS_TARGET" "decisions" \
    | grep -v '^_No decisions recorded yet' > "$CONTENT_FILE" || true

  CHANGED=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TS=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null || true)
    INSIGHT=$(printf '%s' "$line" | jq -r '.insight // empty' 2>/dev/null || true)
    SKILL=$(printf '%s' "$line" | jq -r '.skill // "unknown"' 2>/dev/null || true)
    REPO=$(printf '%s' "$line" | jq -r '.repo // empty' 2>/dev/null || true)
    [ -z "$TS" ] || [ -z "$INSIGHT" ] && continue
    repo_matches_project "$REPO" || continue

    ENTRY_ID="$(printf '%s' "$TS" | tr -cd '0-9' | cut -c1-12)-eureka"
    grep -qF "entry:${ENTRY_ID}" "$DECISIONS_TARGET" 2>/dev/null && continue

    DATE=$(printf '%s' "$TS" | cut -c1-10)
    {
      printf '<!-- entry:%s -->\n' "$ENTRY_ID"
      printf '**%s** (`%s`): %s\n\n' "$DATE" "$SKILL" "$INSIGHT"
    } >> "$CONTENT_FILE"
    CHANGED=true
  done < <(jq -c '.' "$EUREKA" 2>/dev/null)

  $CHANGED && ax_replace_section "$DECISIONS_TARGET" "decisions" "$CONTENT_FILE"
  rm -f "$CONTENT_FILE"
fi

# ── Session History from skill-usage.jsonl (last 10) ─────────────────────────
USAGE="$HOME/.gstack/analytics/skill-usage.jsonl"
if [ -f "$USAGE" ]; then
  CONTENT_FILE=$(mktemp)
  ax_get_section "$MEMORY" "session-history" \
    | grep -v '^_No sessions recorded yet' > "$CONTENT_FILE" || true

  CHANGED=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TS=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null || true)
    SKILL=$(printf '%s' "$line" | jq -r '.skill // empty' 2>/dev/null || true)
    REPO=$(printf '%s' "$line" | jq -r '.repo // empty' 2>/dev/null || true)
    [ -z "$TS" ] || [ -z "$SKILL" ] && continue
    repo_matches_project "$REPO" || continue

    ENTRY_ID="$(printf '%s' "$TS" | tr -cd '0-9' | cut -c1-12)-skill"
    grep -qF "entry:${ENTRY_ID}" "$MEMORY" 2>/dev/null && continue

    OUTCOME=$(printf '%s' "$line" | jq -r '.outcome // "-"' 2>/dev/null || true)
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
    CHANGED=true
  done < <(tail -15 "$USAGE")

  $CHANGED && ax_replace_section "$MEMORY" "session-history" "$CONTENT_FILE"
  rm -f "$CONTENT_FILE"
fi
