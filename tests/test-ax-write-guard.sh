#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

GUARD="$(cd "$(dirname "$0")/.." && pwd)/hooks/ax-write-guard.sh"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PLUGIN_ROOT
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# Helper: run guard with a mocked usage percentage
run_guard() {
  local tool="$1" pct="$2" project_root="${3:-/tmp}"
  local input
  input=$(printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"/tmp/foo.txt"}}' "$tool" "$project_root")
  # Inject mock usage via env override
  export _AX_USAGE_CACHE=$(mktemp)
  export _AX_USAGE_CACHE_TTL=3600
  python3 -c "import json,time; json.dump({'ts':time.time(),'pct':$pct,'resets':'2026-04-02T20:00:00Z'},open('$_AX_USAGE_CACHE','w'))"
  OUT=$(printf '%s' "$input" | bash "$GUARD" 2>/dev/null); EC=$?
  rm -f "$_AX_USAGE_CACHE"
  unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL
  printf '%s\n%s' "$EC" "$OUT"
}

# Test 1: below warn_at (70%) → exit 0, no message
RESULT=$(run_guard "Bash" "70")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "below warn: exit 0" || fail "below warn: exit $EC"

# Test 2: at warn_at (80%) → exit 0, warning in output
RESULT=$(run_guard "Bash" "80")
EC=$(printf '%s' "$RESULT" | head -1)
MSG=$(printf '%s' "$RESULT" | tail -n +2)
[ "$EC" = "0" ] && ok "at warn: exit 0 (tool proceeds)" || fail "at warn: exit $EC"
printf '%s' "$MSG" | grep -q "80%" && ok "at warn: contains pct" || fail "at warn: no pct in: $MSG"

# Test 3: at pause_at (90%), non-Write/Edit tool → exit 2
RESULT=$(run_guard "Bash" "90")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "2" ] && ok "at pause: Bash blocked" || fail "at pause: Bash exit $EC"

# Test 4: at pause_at (90%), Write tool → exit 0 (allowed to save task)
RESULT=$(run_guard "Write" "90")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "0" ] && ok "at pause: Write allowed" || fail "at pause: Write exit $EC"

# Test 5: at block_at (100%), Write tool → exit 2 (all blocked)
RESULT=$(run_guard "Write" "100")
EC=$(printf '%s' "$RESULT" | head -1)
[ "$EC" = "2" ] && ok "at block: Write blocked" || fail "at block: Write exit $EC"

# Test 6: write guard still blocks .ax/memory/ writes below thresholds
TMPDIR_AX=$(mktemp -d)
mkdir -p "$TMPDIR_AX/.ax/memory"
INPUT=$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/.ax/memory/MEMORY.md"}}' "$TMPDIR_AX" "$TMPDIR_AX")
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=3600
python3 -c "import json,time; json.dump({'ts':time.time(),'pct':10,'resets':''},open('$_AX_USAGE_CACHE','w'))"
printf '%s' "$INPUT" | bash "$GUARD" >/dev/null 2>&1 && EC=0 || EC=$?
rm -f "$_AX_USAGE_CACHE"
unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL
rm -rf "$TMPDIR_AX"
[ "$EC" = "2" ] && ok "write-guard: .ax/memory/ still blocked at 10%" || fail "write-guard: exit $EC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
