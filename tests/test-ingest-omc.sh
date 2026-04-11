#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/adapters/ingest-omc.sh"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PLUGIN_ROOT/lib/ax-utils.sh"

TEST_ROOT="/tmp/ax-test-project-$$"

setup() {
  mkdir -p "$TEST_ROOT/.omc/state"
  mkdir -p "$TEST_ROOT/.ax/memory"

  cat > "$TEST_ROOT/.omc/project-memory.json" << 'EOF'
{
  "entries": [
    {"id": "abc12345", "content": "Rate limit handled by ax-resume-watcher.sh", "createdAt": "2026-04-10T10:00:00Z"},
    {"id": "def67890", "content": "Always use git -C instead of cd in hooks", "createdAt": "2026-04-09T09:00:00Z"}
  ]
}
EOF

  cat > "$TEST_ROOT/.ax/memory/MEMORY.md" << 'MEMEOF'
<!-- BEGIN:active-context -->
_No active context._
<!-- END:active-context -->
<!-- BEGIN:session-history -->
_No sessions recorded yet.
<!-- END:session-history -->
MEMEOF

  cat > "$TEST_ROOT/.ax/memory/decisions.md" << 'DECEOF'
<!-- BEGIN:decisions -->
_No decisions recorded yet.
<!-- END:decisions -->
DECEOF
}

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

setup

# Run ingest
bash "$SCRIPT" "$TEST_ROOT" 2>/dev/null

# Test 1: first entry content in decisions.md
grep -q "ax-resume-watcher" "$TEST_ROOT/.ax/memory/decisions.md" \
  && ok "project-memory entry 1 ingested" \
  || fail "project-memory entry 1 missing"

# Test 2: second entry content in decisions.md
grep -q "git -C" "$TEST_ROOT/.ax/memory/decisions.md" \
  && ok "project-memory entry 2 ingested" \
  || fail "project-memory entry 2 missing"

# Test 3: no duplicate on re-run (entry ID dedup)
bash "$SCRIPT" "$TEST_ROOT" 2>/dev/null
COUNT=$(grep -c "ax-resume-watcher" "$TEST_ROOT/.ax/memory/decisions.md" || true)
[ "$COUNT" = "1" ] && ok "no duplicate on re-run" || fail "duplicate entry on re-run (count=$COUNT)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
