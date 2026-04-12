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

# --- Test: 이미 최신 버전이면 재실행해도 중복 append 없음 ---
{
  PROJ=$(mktemp -d "$TMPDIR_ROOT/proj-XXXX")
  TOPIC_FILE="$PROJ/topic.md"
  TEMPLATE_FILE="$PROJ/template.md"

  cat > "$TEMPLATE_FILE" << 'DOCEOF'
<!-- ax-template-version: 3 -->
# Study Notes

<!-- BEGIN:active-document -->
_empty_
<!-- END:active-document -->

## Mastery
<!-- BEGIN:mastery -->
_No mastery data yet._
<!-- END:mastery -->
DOCEOF

  # 파일이 이미 버전 3이고 mastery 있음
  cat > "$TOPIC_FILE" << 'DOCEOF'
<!-- ax-template-version: 3 -->
# Study Notes

<!-- BEGIN:active-document -->
custom content
<!-- END:active-document -->

## Mastery
<!-- BEGIN:mastery -->
- SomeConcept: feynman-passed
<!-- END:mastery -->
DOCEOF

  ax_migrate_topic_file "$TOPIC_FILE" "$TEMPLATE_FILE"

  # 기존 내용 보존 확인
  if grep -q 'custom content' "$TOPIC_FILE" && grep -q 'feynman-passed' "$TOPIC_FILE"; then
    ok "버전 동일 시 기존 내용 보존됨"
  else
    fail "버전 동일 시 기존 내용이 손상됨"
  fi

  # 중복 append 없음 확인
  count=$(grep -c '<!-- BEGIN:mastery -->' "$TOPIC_FILE" || true)
  if [ "$count" -eq 1 ]; then
    ok "섹션 중복 없음 (count=$count)"
  else
    fail "섹션이 중복 append됨 (count=$count)"
  fi
}

# --- Test: 이전 버전 파일에만 migration 실행됨 ---
{
  PROJ=$(mktemp -d "$TMPDIR_ROOT/proj-XXXX")
  TOPIC_FILE="$PROJ/topic.md"
  TEMPLATE_FILE="$PROJ/template.md"

  cat > "$TEMPLATE_FILE" << 'DOCEOF'
<!-- ax-template-version: 5 -->
# Notes

<!-- BEGIN:existing -->
_default_
<!-- END:existing -->

## New Section
<!-- BEGIN:new-section -->
_new default_
<!-- END:new-section -->
DOCEOF

  cat > "$TOPIC_FILE" << 'DOCEOF'
<!-- ax-template-version: 4 -->
# Notes

<!-- BEGIN:existing -->
user data here
<!-- END:existing -->
DOCEOF

  ax_migrate_topic_file "$TOPIC_FILE" "$TEMPLATE_FILE"

  # new-section이 추가되었는지
  if grep -q '<!-- BEGIN:new-section -->' "$TOPIC_FILE"; then
    ok "이전 버전 파일에 새 섹션 추가됨"
  else
    fail "이전 버전 파일에 새 섹션이 추가되지 않음"
  fi

  # 기존 user data 보존
  if grep -q 'user data here' "$TOPIC_FILE"; then
    ok "기존 user data 보존됨"
  else
    fail "기존 user data 손상됨"
  fi

  # 버전 헤더 업데이트
  if grep -q 'ax-template-version: 5' "$TOPIC_FILE"; then
    ok "버전 헤더가 5로 업데이트됨"
  else
    fail "버전 헤더 업데이트 실패"
  fi
}

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
