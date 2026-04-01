#!/usr/bin/env bash
# ingest-research.sh — pulls research skill outputs into project MEMORY.md
# Usage: ingest-research.sh [PROJECT_ROOT]
#
# Sources (project-local, all optional):
#   PAPER_PLAN.md              → research-notes (paper outline)
#   PAPER_IMPROVEMENT_LOG.md   → research-notes (improvement history)
#   EXPERIMENT_LOG.md          → research-notes (experiment runs)
#   CLAIMS_FROM_RESULTS.md     → research-notes (validated claims)
#   AUTO_REVIEW.md             → research-notes (paper review)
#   NARRATIVE_REPORT.md        → research-notes (research narrative)
#   refine-logs/FINAL_PROPOSAL.md → research-notes (experiment proposal)

set -euo pipefail
CONTENT_FILE=""
trap 'rm -f "${CONTENT_FILE:-}"' EXIT

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"

[ -f "$MEMORY" ] || exit 0

# shellcheck source=../lib/ax-utils.sh
source "$HOME/.ax/lib/ax-utils.sh"

# File → (label, section) mapping
declare -A RESEARCH_FILES=(
  ["PAPER_PLAN.md"]="Paper Plan"
  ["PAPER_IMPROVEMENT_LOG.md"]="Paper Improvement Log"
  ["EXPERIMENT_LOG.md"]="Experiment Log"
  ["CLAIMS_FROM_RESULTS.md"]="Claims from Results"
  ["AUTO_REVIEW.md"]="Paper Review"
  ["NARRATIVE_REPORT.md"]="Research Narrative"
  ["refine-logs/FINAL_PROPOSAL.md"]="Experiment Proposal"
)

CONTENT_FILE=$(mktemp)
ax_get_section "$MEMORY" "research-notes" \
  | grep -v '^_No research notes yet' > "$CONTENT_FILE" || true

mapfile -t EXISTING_IDS < <(ax_get_entry_ids "$MEMORY" "research-notes")

NEW_COUNT=0

for REL_PATH in "${!RESEARCH_FILES[@]}"; do
  FULL_PATH="$PROJECT_ROOT/$REL_PATH"
  [ -f "$FULL_PATH" ] || continue

  LABEL="${RESEARCH_FILES[$REL_PATH]}"

  # Entry ID based on file modification time (changes when file is updated)
  MTIME=$(stat -c %Y "$FULL_PATH" 2>/dev/null || echo 0)
  FILE_SLUG=$(printf '%s' "$REL_PATH" | tr '/_.' '---' | cut -c1-20)
  ENTRY_ID="${MTIME}-${FILE_SLUG}"

  # Skip if already ingested at this mtime
  printf '%s\n' "${EXISTING_IDS[@]+"${EXISTING_IDS[@]}"}" | grep -qF "$ENTRY_ID" && continue

  # Extract first meaningful line (skip empty/heading lines)
  SUMMARY=$(grep -v '^#\|^$\|^---\|^==' "$FULL_PATH" 2>/dev/null | head -3 \
    | tr '\n' ' ' | cut -c1-120 || true)
  [ -z "$SUMMARY" ] && SUMMARY="(no summary)"

  FILE_DATE=$(date -d "@$MTIME" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
  SIZE=$(wc -l < "$FULL_PATH" | tr -d ' ')

  {
    printf '<!-- entry:%s -->\n' "$ENTRY_ID"
    printf '%s\n' "- **${FILE_DATE}** ${LABEL} (\`${REL_PATH}\`, ${SIZE} lines): ${SUMMARY}"
  } >> "$CONTENT_FILE"
  NEW_COUNT=$((NEW_COUNT + 1))
done

if [ "$NEW_COUNT" -gt 0 ]; then
  ax_replace_section "$MEMORY" "research-notes" "$CONTENT_FILE"
elif [ ! -s "$CONTENT_FILE" ]; then
  printf '_No research notes yet._\n' > "$CONTENT_FILE"
  ax_replace_section "$MEMORY" "research-notes" "$CONTENT_FILE"
fi

rm -f "$CONTENT_FILE"
