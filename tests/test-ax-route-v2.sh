#!/usr/bin/env bash
# tests/test-ax-route-v2.sh — AX Router v2 Tier 0/1/2/3 unit tests
set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ROUTE_BIN="$PLUGIN_ROOT/bin/ax-route.py"
ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"

[ -f "$ROUTE_BIN" ] || { echo "ERROR: ax-route.py not found at $ROUTE_BIN"; exit 1; }
[ -f "$ROUTING" ]   || { echo "ERROR: skill-routing.yaml not found"; exit 1; }
command -v python3  >/dev/null 2>&1 || { echo "ERROR: python3 required"; exit 1; }

run_route() { python3 "$ROUTE_BIN" "$1" "$ROUTING" 2>/dev/null || true; }

assert_empty() {
  local desc="$1" input="$2"
  local out; out=$(run_route "$input")
  if [ -z "$out" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc — expected empty, got: $out"; FAIL=$((FAIL+1))
  fi
}

assert_field() {
  local desc="$1" input="$2" field="$3" expected="$4"
  local out; out=$(run_route "$input")
  local val; val=$(printf '%s' "$out" | grep "^${field}=" | cut -d= -f2- || true)
  if [ "$val" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc — expected ${field}=${expected}, got: ${field}=${val:-<empty>} (full=$out)"; FAIL=$((FAIL+1))
  fi
}

assert_field_exists() {
  local desc="$1" input="$2" field="$3"
  local out; out=$(run_route "$input")
  if printf '%s' "$out" | grep -q "^${field}="; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc — expected ${field}= field, got: $out"; FAIL=$((FAIL+1))
  fi
}

# ── Tier 0: Informational Filter ─────────────────────────────────────────────
echo "=== Tier 0: Informational Filter ==="
assert_empty  "T0-1: 'ralph가 뭐야?' exits silently"       "ralph가 뭐야?"
assert_empty  "T0-2: 'what is traceback' exits silently"   "what is traceback"
assert_empty  "T0-3: 'traceback이 뭔데?' exits silently"   "traceback이 뭔데?"
assert_empty  "T0-4: 'how to use arxiv' exits silently"    "how to use arxiv"
assert_empty  "T0-5: '설명해줘 traceback' exits silently"  "설명해줘 traceback"
assert_field  "T0-6: action override cancels filter"       "버그 fix해줘" "MATCH" "debugging"

# ── Tier 1: Exact keyword match (regression) ──────────────────────────────────
echo "=== Tier 1: Exact match regression ==="
assert_field  "T1-1: '버그' → debugging"                  "버그 고쳐줘"     "MATCH" "debugging"
assert_field  "T1-2: '논문 써' → research_paper (orch)"   "논문 써줘"       "MATCH" "research_paper"
assert_field  "T1-3: 'traceback' → debugging"             "traceback 발생"  "MATCH" "debugging"
assert_field  "T1-4: 'ship' → ship_deploy"                "git ship"        "MATCH" "ship_deploy"

# ── Tier 2: Fuzzy match ───────────────────────────────────────────────────────
echo "=== Tier 2: Fuzzy match ==="
assert_field       "T2-1: 'trakback' → debugging (영어 오타)"   "trakback 발생"     "MATCH"      "debugging"
assert_field       "T2-2: SOURCE=fuzzy for typo"               "trakback 발생"     "SOURCE"     "fuzzy"
assert_field_exists "T2-3: CONFIDENCE present for fuzzy"        "trakback 발생"     "CONFIDENCE"
assert_field       "T2-4: 'segfalt' → debugging (typo)"        "segfalt 났어"      "MATCH"      "debugging"
assert_field       "T2-5: '논무 써야해' → research_paper (한글)" "논무 써야해"       "MATCH"      "research_paper"
assert_field       "T2-6: 'rivew' → code_review (typo)"        "코드 rivew 해줘"   "MATCH"      "code_review"

# ── Tier 3: TF-IDF match ──────────────────────────────────────────────────────
echo "=== Tier 3: TF-IDF match ==="
# Requires examples: field in skill-routing.yaml (Task 5 adds them)
assert_field       "T3-1: natural lang → debugging (TF-IDF)"   "어디서 죽는지 모르겠어"   "MATCH"      "debugging"
assert_field       "T3-2: SOURCE=tfidf"                         "어디서 죽는지 모르겠어"   "SOURCE"     "tfidf"
assert_field_exists "T3-3: CONFIDENCE present for tfidf"         "어디서 죽는지 모르겠어"   "CONFIDENCE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
