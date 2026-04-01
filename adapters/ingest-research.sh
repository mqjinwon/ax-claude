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
#   IDEA_REPORT.md             → research-notes (idea-discovery output)
#   LITERATURE_REPORT.md       → research-notes (research-lit output)
#   eval_results.json          → experiment-log.md (run-experiment output)

set -euo pipefail
CONTENT_FILE=""
trap 'rm -f "${CONTENT_FILE:-}"' EXIT

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"

[ -f "$MEMORY" ] || exit 0

# shellcheck source=../lib/ax-utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/ax-utils.sh"

# Determine target for research notes (split memory → research-notes.md, legacy → MEMORY.md)
RESEARCH_TARGET="$PROJECT_ROOT/.ax/memory/research-notes.md"
if [ ! -f "$RESEARCH_TARGET" ]; then
  RESEARCH_TARGET="$MEMORY"
fi
RESEARCH_SECTION="research-notes"

# File → (label, section) mapping
declare -A RESEARCH_FILES=(
  ["PAPER_PLAN.md"]="Paper Plan"
  ["PAPER_IMPROVEMENT_LOG.md"]="Paper Improvement Log"
  ["EXPERIMENT_LOG.md"]="Experiment Log"
  ["CLAIMS_FROM_RESULTS.md"]="Claims from Results"
  ["AUTO_REVIEW.md"]="Paper Review"
  ["NARRATIVE_REPORT.md"]="Research Narrative"
  ["refine-logs/FINAL_PROPOSAL.md"]="Experiment Proposal"
  ["IDEA_REPORT.md"]="Idea Discovery Report"
  ["LITERATURE_REPORT.md"]="Literature Report"
)

CONTENT_FILE=$(mktemp)
ax_get_section "$RESEARCH_TARGET" "$RESEARCH_SECTION" \
  | grep -v '^_No research notes yet' > "$CONTENT_FILE" || true

CHANGED=false

for REL_PATH in "${!RESEARCH_FILES[@]}"; do
  FULL_PATH="$PROJECT_ROOT/$REL_PATH"
  [ -f "$FULL_PATH" ] || continue

  LABEL="${RESEARCH_FILES[$REL_PATH]}"

  # Entry ID based on file modification time (changes when file is updated)
  MTIME=$(stat -c %Y "$FULL_PATH" 2>/dev/null || echo 0)
  FILE_SLUG=$(printf '%s' "$REL_PATH" | tr '/_.' '---' | cut -c1-20)
  ENTRY_ID="${MTIME}-${FILE_SLUG}"

  # Skip if already ingested at this mtime
  grep -qF "entry:${ENTRY_ID}" "$RESEARCH_TARGET" 2>/dev/null && continue

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
  CHANGED=true
done

if $CHANGED; then
  ax_replace_section "$RESEARCH_TARGET" "$RESEARCH_SECTION" "$CONTENT_FILE"
elif [ ! -s "$CONTENT_FILE" ]; then
  printf '_No research notes yet._\n' > "$CONTENT_FILE"
  ax_replace_section "$RESEARCH_TARGET" "$RESEARCH_SECTION" "$CONTENT_FILE"
fi

rm -f "$CONTENT_FILE"

# Handle eval_results.json → experiment-log.md
EVAL_JSON="$PROJECT_ROOT/eval_results.json"
if [ -f "$EVAL_JSON" ]; then
  MTIME=$(stat -c %Y "$EVAL_JSON" 2>/dev/null || echo 0)
  ENTRY_ID="${MTIME}-eval-results-json"

  # Check against experiment-log.md existing IDs
  EXPLOG="$PROJECT_ROOT/.ax/memory/experiment-log.md"
  if [ -f "$EXPLOG" ] && ! grep -qF "entry:${ENTRY_ID}" "$EXPLOG" 2>/dev/null; then
    FILE_DATE=$(date -d "@$MTIME" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
    # Extract key metrics from JSON
    SUMMARY=$(python3 -c "
import json, sys
try:
  with open('$EVAL_JSON') as f:
    d = json.load(f)
  keys = list(d.keys())[:5]
  parts = [f'{k}={d[k]}' for k in keys if isinstance(d[k], (int, float, str))]
  print(', '.join(parts[:3]))
except Exception as e:
  print('(parse error)')
" 2>/dev/null || echo "(no summary)")

    EXP_CONTENT=$(mktemp)
    ax_get_section "$EXPLOG" "experiment-log" \
      | grep -v '^_No experiments recorded yet' > "$EXP_CONTENT" || true
    {
      printf '<!-- entry:%s -->\n' "$ENTRY_ID"
      printf '- **%s** eval_results.json: %s\n' "$FILE_DATE" "$SUMMARY"
    } >> "$EXP_CONTENT"
    ax_replace_section "$EXPLOG" "experiment-log" "$EXP_CONTENT"
    rm -f "$EXP_CONTENT"
  fi
fi
