#!/usr/bin/env bash
# tests/test-ax-learn.sh — Unit tests for ax-learn.py
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
LEARN_BIN="$PLUGIN_ROOT/bin/ax-learn.py"
ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"

[ -f "$LEARN_BIN" ] || { echo "SKIP: ax-learn.py not found (not yet implemented)"; exit 0; }
command -v python3  >/dev/null 2>&1 || { echo "ERROR: python3 required"; exit 1; }

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT
mkdir -p "$TMPDIR_BASE/.ax/memory"

# Create sample routing log
cat > "$TMPDIR_BASE/.ax/routing-log.jsonl" << 'EOF'
{"ts":"2026-04-12T00:00:00Z","prompt":"에러가 나는데 어디서 죽는지 모르겠어","category":"debugging","source":"exact","confidence":null}
{"ts":"2026-04-12T00:01:00Z","prompt":"이 코드가 왜 안 돼?","category":"debugging","source":"tfidf","confidence":0.42}
{"ts":"2026-04-12T00:02:00Z","prompt":"완전 새로운 프롬프트인데 어떤 카테고리지","category":null,"source":null,"confidence":null}
{"ts":"2026-04-12T00:03:00Z","prompt":"논문을 작성해야 해","category":"research_paper","source":"fuzzy","confidence":0.78}
EOF

python3 "$LEARN_BIN" "$TMPDIR_BASE" "$ROUTING" 2>/dev/null

SUGGESTIONS="$TMPDIR_BASE/.ax/memory/routing-suggestions.md"

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc — file not found: $path"; FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" path="$2" needle="$3"
  if grep -q "$needle" "$path" 2>/dev/null; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc — '$needle' not in $path"; FAIL=$((FAIL+1))
  fi
}

assert_file_exists "L1: routing-suggestions.md 생성됨"               "$SUGGESTIONS"
assert_contains    "L2: debugging 카테고리 examples 후보 포함"        "$SUGGESTIONS" "debugging"
assert_contains    "L3: unmatched prompt가 trigger 후보로 포함"       "$SUGGESTIONS" "완전 새로운"
assert_contains    "L4: BEGIN 마커 존재"                              "$SUGGESTIONS" "BEGIN:routing-suggestions"
assert_contains    "L5: END 마커 존재"                                "$SUGGESTIONS" "END:routing-suggestions"

# Idempotency: re-run should not duplicate section
python3 "$LEARN_BIN" "$TMPDIR_BASE" "$ROUTING" 2>/dev/null
SECTION_COUNT=$(grep -c "BEGIN:routing-suggestions" "$SUGGESTIONS" 2>/dev/null || echo 0)
if [ "$SECTION_COUNT" -eq 1 ]; then
  echo "PASS: L6: 재실행해도 중복 섹션 없음"; PASS=$((PASS+1))
else
  echo "FAIL: L6: expected 1 section, got $SECTION_COUNT"; FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
