#!/usr/bin/env bash
# ax-usage.sh — Claude Code 5-hour usage fetcher
# Source this file, then call: ax_get_usage
# Sets: FIVE_HOUR_PERCENT (integer 0-100), FIVE_HOUR_RESETS_AT (ISO 8601 or "")

FIVE_HOUR_PERCENT=""
FIVE_HOUR_RESETS_AT=""

_AX_USAGE_CACHE="${_AX_USAGE_CACHE:-/tmp/ax-usage-cache-$(id -u).json}"
_AX_USAGE_CACHE_TTL="${_AX_USAGE_CACHE_TTL:-60}"
_AX_USAGE_API_TIMEOUT=5
_AX_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

_ax_usage_read_token() {
  local f="$_AX_CLAUDE_DIR/.credentials.json"
  [ -f "$f" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$f" << 'PY'
import json, sys
try:
  d = json.load(open(sys.argv[1]))
  c = d.get('claudeAiOauth') or d
  t = c.get('accessToken', '')
  print(t) if t else sys.exit(1)
except Exception: sys.exit(1)
PY
}

# stdin: raw API JSON response
_ax_usage_parse_api_response() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c '
import json, sys
try:
  d = json.load(sys.stdin)
  fh = d.get("five_hour") or {}
  p = fh.get("utilization")
  if p is None: sys.exit(1)
  print(str(int(round(float(p)))) + "\t" + (fh.get("resets_at") or ""))
except Exception: sys.exit(1)
'
}

_ax_usage_read_local_cache() {
  [ -f "$_AX_USAGE_CACHE" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$_AX_USAGE_CACHE" "$_AX_USAGE_CACHE_TTL" << 'PY'
import json, sys, time
try:
  d = json.load(open(sys.argv[1]))
  if time.time() - d['ts'] > int(sys.argv[2]): sys.exit(1)
  print(str(int(d['pct'])) + '\t' + (d.get('resets', '') or ''))
except Exception: sys.exit(1)
PY
}

_ax_usage_write_local_cache() {
  local pct="$1" resets="$2"
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$_AX_USAGE_CACHE" "$pct" "$resets" << 'PY' 2>/dev/null || true
import json, sys, time, os
data = {'ts': time.time(), 'pct': int(sys.argv[2]), 'resets': sys.argv[3]}
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as f:
    json.dump(data, f)
PY
}

_ax_usage_read_omc_cache() {
  local f="$_AX_CLAUDE_DIR/plugins/oh-my-claudecode/.usage-cache.json"
  [ -f "$f" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$f" << 'PY'
import json, sys, time
try:
  d = json.load(open(sys.argv[1]))
  if time.time() - d.get('lastSuccessAt', 0) / 1000 > 900: sys.exit(1)
  data = d.get('data') or {}
  p = data.get('fiveHourPercent')
  if p is None: sys.exit(1)
  print(str(int(round(float(p)))) + '\t' + (data.get('fiveHourResetsAt') or ''))
except Exception: sys.exit(1)
PY
}

# Main entry point — sets FIVE_HOUR_PERCENT and FIVE_HOUR_RESETS_AT
ax_get_usage() {
  FIVE_HOUR_PERCENT=""
  FIVE_HOUR_RESETS_AT=""

  # 1. Local 60s cache (fastest path — avoids API call on every tool use)
  local out
  if out=$(_ax_usage_read_local_cache 2>/dev/null); then
    IFS=$'\t' read -r FIVE_HOUR_PERCENT FIVE_HOUR_RESETS_AT <<< "$out"
    return 0
  fi

  # 2. Anthropic OAuth API
  local token=""
  token=$(_ax_usage_read_token 2>/dev/null) || true
  if [ -n "$token" ]; then
    local response=""
    response=$(curl -sf --max-time "$_AX_USAGE_API_TIMEOUT" \
      "https://api.anthropic.com/api/oauth/usage" \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Content-Type: application/json" 2>/dev/null) || true
    if [ -n "$response" ]; then
      local parsed=""
      parsed=$(printf '%s' "$response" | _ax_usage_parse_api_response 2>/dev/null) || true
      if [ -n "$parsed" ]; then
        IFS=$'\t' read -r FIVE_HOUR_PERCENT FIVE_HOUR_RESETS_AT <<< "$parsed"
        _ax_usage_write_local_cache "$FIVE_HOUR_PERCENT" "$FIVE_HOUR_RESETS_AT"
        return 0
      fi
    fi
  fi

  # 3. omc cache fallback (stale ok up to 15 min)
  if out=$(_ax_usage_read_omc_cache 2>/dev/null); then
    IFS=$'\t' read -r FIVE_HOUR_PERCENT FIVE_HOUR_RESETS_AT <<< "$out"
    _ax_usage_write_local_cache "$FIVE_HOUR_PERCENT" "$FIVE_HOUR_RESETS_AT"
    return 0
  fi

  return 1
}
