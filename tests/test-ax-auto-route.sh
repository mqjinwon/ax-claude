#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/hooks/ax-auto-route.sh"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PLUGIN_ROOT
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

run_hook() {
  local prompt="$1"
  local input
  input=$(printf '{"prompt":"%s","cwd":"/tmp","session_id":"test-123"}' "$prompt")
  OUT=$(printf '%s' "$input" | bash "$SCRIPT" 2>/dev/null); EC=$?
  printf '%s\n%s' "$EC" "$OUT"
}

# Test 1: no match → exit 0, empty output
RESULT=$(run_hook "오늘 날씨 어때")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "no match: exit 0" || fail "no match: exit $EC"
BODY=$(printf '%s' "$RESULT" | tail -n +2)
[ -z "$BODY" ] && ok "no match: empty output" || fail "no match: got output: $BODY"

# Test 2: debug prompt → skill suggestion in additionalContext
RESULT=$(run_hook "버그가 생겼어")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "debug match: exit 0" || fail "debug match: exit $EC"
BODY=$(printf '%s' "$RESULT" | tail -n +2)
printf '%s' "$BODY" | grep -q "oh-my-claudecode:trace" \
  && ok "debug match: skill in output" \
  || fail "debug match: skill not found in: $BODY"
printf '%s' "$BODY" | grep -q "additionalContext" \
  && ok "debug match: additionalContext key present" \
  || fail "debug match: no additionalContext in: $BODY"

# Test 3: omc_covered → exit 0, empty output (no duplicate)
RESULT=$(run_hook "코드 리뷰 해줘")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "omc_covered: exit 0" || fail "omc_covered: exit $EC"
BODY=$(printf '%s' "$RESULT" | tail -n +2)
[ -z "$BODY" ] && ok "omc_covered: empty output (no duplicate)" || fail "omc_covered: got output: $BODY"

# Test 4: paper prompt → some output (non-omc_covered match)
RESULT=$(run_hook "논문 써야 해")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "paper match: exit 0" || fail "paper match: exit $EC"
BODY=$(printf '%s' "$RESULT" | tail -n +2)
[ -n "$BODY" ] && ok "paper match: has output" || fail "paper match: empty output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
