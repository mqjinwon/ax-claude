#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$SCRIPT_DIR"

# Setup a fake project
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.ax"

# Test 1: --trigger with no task file → exits 0, no watcher launched
INPUT=$(printf '{"cwd":"%s"}' "$PROJ")
printf '%s' "$INPUT" | bash "$SCRIPT_DIR/adapters/ax-resume-watcher.sh" --trigger
[ ! -f "$PROJ/.ax/resume-watcher.pid" ] && ok "--trigger: no task file → no watcher" || fail "--trigger: unexpected pid file"

# Test 2: --trigger with task file but usage < 100% → no watcher
echo "implement feature X" > "$PROJ/.ax/resume-task.txt"
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=3600
python3 -c "import json,time; json.dump({'ts':time.time(),'pct':50,'resets':'2026-04-02T20:00:00Z'},open('$_AX_USAGE_CACHE','w'))"
printf '%s' "$INPUT" | bash "$SCRIPT_DIR/adapters/ax-resume-watcher.sh" --trigger
[ ! -f "$PROJ/.ax/resume-watcher.pid" ] && ok "--trigger: 50% → no watcher" || fail "--trigger: 50% unexpected pid"
rm -f "$_AX_USAGE_CACHE"
unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL

# Test 2b: --trigger with auto_resume: false → no watcher even at 100%
echo "some task" > "$PROJ/.ax/resume-task.txt"
mkdir -p "$PROJ/.ax"
printf 'auto_resume: false\n' > "$PROJ/.ax/config.yaml"
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=3600
python3 -c "import json,time; json.dump({'ts':time.time(),'pct':100,'resets':'2099-01-01T00:00:00Z'},open('$_AX_USAGE_CACHE','w'))"
printf '%s' "$INPUT" | bash "$SCRIPT_DIR/adapters/ax-resume-watcher.sh" --trigger
[ ! -f "$PROJ/.ax/resume-watcher.pid" ] && ok "--trigger: auto_resume=false → no watcher" || fail "--trigger: auto_resume=false unexpected watcher"
rm -f "$_AX_USAGE_CACHE" "$PROJ/.ax/resume-task.txt" "$PROJ/.ax/config.yaml"
unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL

# Test 3: --trigger with task file + usage = 100% → watcher launched
echo "implement feature X" > "$PROJ/.ax/resume-task.txt"
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=3600
FUTURE=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(seconds=5)).isoformat())")
python3 -c "import json,time; json.dump({'ts':time.time(),'pct':100,'resets':'$FUTURE'},open('$_AX_USAGE_CACHE','w'))"
printf '%s' "$INPUT" | bash "$SCRIPT_DIR/adapters/ax-resume-watcher.sh" --trigger
sleep 1  # give nohup time to write pid file
[ -f "$PROJ/.ax/resume-watcher.pid" ] && ok "--trigger: 100% → watcher PID created" || fail "--trigger: 100% no pid file"
# Kill the watcher to avoid actual claude invocation
PID=$(cat "$PROJ/.ax/resume-watcher.pid" 2>/dev/null || echo "")
[ -n "$PID" ] && kill "$PID" 2>/dev/null || true
rm -f "$_AX_USAGE_CACHE" "$PROJ/.ax/resume-watcher.pid" "$PROJ/.ax/resume-task.txt"
unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL

# Test 4: --trigger when watcher already running → skip (no duplicate)
echo "some task" > "$PROJ/.ax/resume-task.txt"
# Create a fake long-running process as the "watcher"
sleep 60 &
FAKE_PID=$!
echo "$FAKE_PID" > "$PROJ/.ax/resume-watcher.pid"
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=3600
python3 -c "import json,time; json.dump({'ts':time.time(),'pct':100,'resets':'2099-01-01T00:00:00Z'},open('$_AX_USAGE_CACHE','w'))"
printf '%s' "$INPUT" | bash "$SCRIPT_DIR/adapters/ax-resume-watcher.sh" --trigger
sleep 0.5
CURRENT_PID=$(cat "$PROJ/.ax/resume-watcher.pid" 2>/dev/null || echo "0")
kill "$FAKE_PID" 2>/dev/null || true
rm -f "$_AX_USAGE_CACHE"
unset _AX_USAGE_CACHE _AX_USAGE_CACHE_TTL
[ "$CURRENT_PID" = "$FAKE_PID" ] && ok "--trigger: duplicate watcher prevented" || fail "--trigger: pid changed to $CURRENT_PID"

rm -rf "$PROJ"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
