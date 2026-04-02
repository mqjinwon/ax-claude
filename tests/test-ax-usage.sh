#!/usr/bin/env bash
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/ax-usage.sh"

# --- Test 1: parse API response ---
RESPONSE='{"five_hour":{"utilization":73.5,"resets_at":"2026-04-02T19:00:00Z"},"seven_day":{"utilization":50.0}}'
TMPF=$(mktemp)
printf '%s' "$RESPONSE" > "$TMPF"
PARSED=$(cat "$TMPF" | _ax_usage_parse_api_response 2>/dev/null)
IFS=$'\t' read -r PCT RESETS <<< "$PARSED"
rm -f "$TMPF"
[ "$PCT" = "74" ] && ok "parse_api: rounds 73.5 → 74" || fail "parse_api: got $PCT"
[ "$RESETS" = "2026-04-02T19:00:00Z" ] && ok "parse_api: resets_at" || fail "parse_api resets: $RESETS"

# --- Test 2: parse API response with 100% ---
RESPONSE2='{"five_hour":{"utilization":100.0,"resets_at":"2026-04-02T20:00:00Z"}}'
PARSED2=$(printf '%s' "$RESPONSE2" | _ax_usage_parse_api_response 2>/dev/null)
IFS=$'\t' read -r PCT2 _RESETS2 <<< "$PARSED2"
[ "$PCT2" = "100" ] && ok "parse_api: 100% exact" || fail "parse_api 100: got $PCT2"

# --- Test 3: local cache write + read ---
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=60
_ax_usage_write_local_cache "42" "2026-04-02T20:00:00Z"
CACHED=$(_ax_usage_read_local_cache 2>/dev/null)
IFS=$'\t' read -r CPCT _CRESETS <<< "$CACHED"
[ "$CPCT" = "42" ] && ok "local cache: read back pct" || fail "local cache: got $CPCT"
rm -f "$_AX_USAGE_CACHE"

# --- Test 4: stale local cache returns non-zero ---
export _AX_USAGE_CACHE=$(mktemp)
export _AX_USAGE_CACHE_TTL=0  # TTL=0 → always stale
_ax_usage_write_local_cache "99" ""
_ax_usage_read_local_cache 2>/dev/null && fail "stale cache: should fail" || ok "stale cache: correctly fails"
rm -f "$_AX_USAGE_CACHE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
