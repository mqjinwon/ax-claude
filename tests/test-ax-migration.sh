#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_ROOT/lib/ax-utils.sh"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

echo "=== test-ax-migration ==="

# --- Test: 누락 섹션이 append되는지 확인 ---
{
  PROJ=$(mktemp -d "$TMPDIR_ROOT/proj-XXXX")
  TOPIC_FILE="$PROJ/topic.md"
  TEMPLATE_FILE="$PROJ/template.md"

  # 기존 파일: mastery 섹션 없음
  cat > "$TOPIC_FILE" << 'DOCEOF'
# Study Notes

<!-- BEGIN:active-document -->
_No document loaded yet._
<!-- END:active-document -->
DOCEOF

  # 템플릿: mastery 섹션 포함
  cat > "$TEMPLATE_FILE" << 'DOCEOF'
<!-- ax-template-version: 2 -->
# Study Notes

<!-- BEGIN:active-document -->
_No document loaded yet._
<!-- END:active-document -->

## Mastery
<!-- BEGIN:mastery -->
_No mastery data yet._
<!-- END:mastery -->
DOCEOF

  ax_migrate_topic_file "$TOPIC_FILE" "$TEMPLATE_FILE"

  if grep -q '<!-- BEGIN:mastery -->' "$TOPIC_FILE"; then
    ok "누락 섹션(mastery)이 append됨"
  else
    fail "누락 섹션(mastery)이 append되지 않음"
  fi
}

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
