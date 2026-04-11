#!/usr/bin/env bash
# ax-auto-route.sh — UserPromptSubmit hook
# Detects relevant skill for current prompt and suggests it via additionalContext.
# Outputs nothing (exit 0) when no match or when OMC already covers the skill.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0
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

# Run keyword routing
ROUTE_OUT=$(python3 "$ROUTE_BIN" "$PROMPT" "$ROUTING" 2>/dev/null || true)
[ -n "$ROUTE_OUT" ] || exit 0

CANONICAL=$(printf '%s' "$ROUTE_OUT" | grep '^CANONICAL=' | cut -d= -f2-)
MATCH=$(printf '%s' "$ROUTE_OUT" | grep '^MATCH=' | cut -d= -f2-)
[ -n "$CANONICAL" ] || exit 0

# Check omc_covered: suppress if OMC keyword-detector already handles this category
OMC_COVERED=$(python3 - "$ROUTING" "$MATCH" << 'PY' 2>/dev/null || echo "false"
import sys, yaml
routing_path, category = sys.argv[1], sys.argv[2]
with open(routing_path) as f:
    data = yaml.safe_load(f)
cats = data.get("categories", {})
cat = cats.get(category, {})
print("true" if cat.get("omc_covered") else "false")
PY
)
[ "$OMC_COVERED" = "true" ] && exit 0

# Build suggestion message and escape for JSON
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

MSG="💡 **AX Router**: 이 작업에 \`/${CANONICAL}\`이 적합합니다.\n사용할까요? (yes → 바로 실행, 아니면 그냥 진행)"
MSG_ESC=$(escape_for_json "$MSG")

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$MSG_ESC"
exit 0
