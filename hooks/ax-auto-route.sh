#!/usr/bin/env bash
# ax-auto-route.sh — UserPromptSubmit hook
# Detects relevant skill for current prompt and suggests it via additionalContext.
# Logs all matches/non-matches to .ax/routing-log.jsonl when project is ax-initialized.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
command -v jq     >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Resolve plugin root
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"
ROUTE_BIN="$PLUGIN_ROOT/bin/ax-route.py"
[ -f "$ROUTING" ]   || exit 0
[ -f "$ROUTE_BIN" ] || exit 0

# Extract prompt text from hook payload
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -n "$PROMPT" ] || exit 0

# Resolve project root for logging
PROJECT_ROOT=""
if command -v git >/dev/null 2>&1; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
LOG_FILE=""
if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT/.ax" ]; then
  LOG_FILE="$PROJECT_ROOT/.ax/routing-log.jsonl"
fi

# Helper: JSON-encode prompt string
json_prompt() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

# Helper: append log entry and roll to 500 lines
append_log() {
  local category="$1" source="$2" confidence="$3"
  [ -n "$LOG_FILE" ] || return 0
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
  local prompt_json; prompt_json=$(json_prompt "$PROMPT")
  local conf_val="$confidence"
  python3 -c "
import json, sys
ts, prompt, category, source, conf = sys.argv[1:]
entry = {
    'ts': ts,
    'prompt': json.loads(prompt),
    'category': None if category == 'null' else category,
    'source': None if source == 'null' else source,
    'confidence': None if conf == 'null' else float(conf),
}
print(json.dumps(entry, ensure_ascii=False))
" "$ts" "$prompt_json" "$category" "$source" "$conf_val" >> "$LOG_FILE" 2>/dev/null || true
  # Rolling: keep last 500 lines
  local line_count; line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$line_count" -gt 500 ]; then
    local tmp; tmp=$(mktemp "${LOG_FILE}.XXXXXX")
    tail -n 500 "$LOG_FILE" > "$tmp"
    mv "$tmp" "$LOG_FILE"
  fi
}

# Run keyword routing
ROUTE_OUT=$(python3 "$ROUTE_BIN" "$PROMPT" "$ROUTING" 2>/dev/null || true)

# No match → log unmatched and exit silently
if [ -z "$ROUTE_OUT" ]; then
  append_log "null" "null" "null"
  exit 0
fi

CANONICAL=$(printf '%s' "$ROUTE_OUT" | grep '^CANONICAL=' | cut -d= -f2- || true)
MATCH=$(printf '%s' "$ROUTE_OUT" | grep '^MATCH=' | cut -d= -f2- || true)
CONFIDENCE=$(printf '%s' "$ROUTE_OUT" | grep '^CONFIDENCE=' | head -1 | cut -d= -f2- || true)
SOURCE=$(printf '%s' "$ROUTE_OUT" | grep '^SOURCE=' | head -1 | cut -d= -f2- || true)

[ -n "$CANONICAL" ] || exit 0
[ -n "$MATCH" ]     || exit 0

# Check omc_covered: suppress if OMC keyword-detector already handles this category
OMC_COVERED=$(python3 - "$ROUTING" "$MATCH" << 'PY' 2>/dev/null || echo "false"
import sys, yaml
routing_path, category = sys.argv[1], sys.argv[2]
with open(routing_path) as f:
    data = yaml.safe_load(f)
cat = data.get("categories", {}).get(category, {})
print("true" if cat.get("omc_covered") else "false")
PY
)
[ "$OMC_COVERED" = "true" ] && exit 0

# Log matched prompt
CONF_LOG="${CONFIDENCE:-null}"
SRC_LOG="${SOURCE:-exact}"
append_log "$MATCH" "$SRC_LOG" "$CONF_LOG"

# Build suggestion message: 💡 if exact/high-confidence, 🤔 if low confidence
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

SUFFIX=""
if [ -n "$CONFIDENCE" ] && ! awk -v c="$CONFIDENCE" 'BEGIN{exit !(c >= 0.85)}' 2>/dev/null; then
  PREFIX="🤔 **AX Router**"
  SUFFIX=" (낮은 확신 — 확인 권장)"
else
  PREFIX="💡 **AX Router**"
fi
MSG="${PREFIX}: 이 작업에 \`/${CANONICAL}\`이 적합합니다.${SUFFIX}\n사용할까요? (yes → 바로 실행, 아니면 그냥 진행)"
MSG_ESC=$(escape_for_json "$MSG")

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$MSG_ESC"
exit 0
