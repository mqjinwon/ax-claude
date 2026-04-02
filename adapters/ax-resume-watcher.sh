#!/usr/bin/env bash
# ax-resume-watcher.sh — Claude Code auto-resume watcher
#
# Modes:
#   --trigger             Called by Stop hook; launches --watch if rate limited + task queued
#   --watch PROJECT_ROOT  Background watcher; sleeps until reset, then calls claude --continue

set -euo pipefail

# Resolve plugin root from env or script location (survives nohup/detach)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Source usage library
# shellcheck source=../lib/ax-usage.sh
source "$PLUGIN_ROOT/lib/ax-usage.sh"

_rl_config() {
  local cfg="$1" key="$2" default="$3"
  [ -f "$cfg" ] || { printf '%s' "$default"; return; }
  python3 - "$cfg" "$key" "$default" << 'PY' 2>/dev/null || printf '%s' "$default"
import sys, re
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
  m = re.search(r'^\s*' + re.escape(key) + r'\s*:\s*(\S+)', open(path).read(), re.M)
  val = m.group(1) if m else default
  try:
    print(int(val))
  except (ValueError, TypeError):
    print(val)
except Exception: print(default)
PY
}

_read_project_root() {
  local stdin_data=""
  if [ ! -t 0 ]; then
    stdin_data=$(cat 2>/dev/null || true)
  fi
  local root=""
  if [ -n "$stdin_data" ] && command -v jq >/dev/null 2>&1; then
    root=$(printf '%s' "$stdin_data" | jq -r '.cwd // empty' 2>/dev/null || true)
  fi
  [ -z "$root" ] && root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  printf '%s' "$root"
}

_iso_to_epoch() {
  python3 -c "
from datetime import datetime, timezone
dt = datetime.fromisoformat('$1'.replace('Z','+00:00'))
print(int(dt.timestamp()))
" 2>/dev/null || echo "0"
}

case "${1:-}" in

  --trigger)
    PROJECT_ROOT=$(_read_project_root)
    [ -d "$PROJECT_ROOT/.ax" ] || exit 0

    CFG="$PROJECT_ROOT/.ax/config.yaml"
    TASK_FILE="$PROJECT_ROOT/.ax/resume-task.txt"
    PID_FILE="$PROJECT_ROOT/.ax/resume-watcher.pid"
    LOG="$PROJECT_ROOT/.ax/resume-watcher.log"

    [ -f "$TASK_FILE" ] || exit 0
    [ "$(_rl_config "$CFG" "auto_resume" "true")" = "false" ] && exit 0

    ax_get_usage 2>/dev/null || exit 0
    [ -n "${FIVE_HOUR_PERCENT:-}" ] || exit 0

    BLOCK_AT=$(_rl_config "$CFG" "block_at" "100")
    [ "$FIVE_HOUR_PERCENT" -ge "$BLOCK_AT" ] || exit 0

    # Skip if watcher already running
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
      if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
      fi
      rm -f "$PID_FILE"
    fi

    # Ensure claude is on PATH for the nohup process
    CLAUDE_PATH=$(command -v claude 2>/dev/null || echo "$HOME/.claude/local/claude")
    export PATH="$PATH:$(dirname "$CLAUDE_PATH")"

    nohup bash "$0" --watch "$PROJECT_ROOT" >> "$LOG" 2>&1 &
    WATCHER_PID=$!
    echo "$WATCHER_PID" > "$PID_FILE"
    printf '[ax-resume-watcher] PID=%s resets_at=%s\n' \
      "$WATCHER_PID" "${FIVE_HOUR_RESETS_AT:-unknown}" >> "$LOG"
    ;;

  --watch)
    PROJECT_ROOT="${2:-}"
    [ -n "$PROJECT_ROOT" ] || exit 1

    TASK_FILE="$PROJECT_ROOT/.ax/resume-task.txt"
    PID_FILE="$PROJECT_ROOT/.ax/resume-watcher.pid"
    LOG="$PROJECT_ROOT/.ax/resume-watcher.log"

    printf '[%s] Watcher started for %s\n' "$(date -u +%FT%TZ)" "$PROJECT_ROOT"

    # Calculate sleep duration
    ax_get_usage 2>/dev/null || true
    SLEEP_SECS=18030  # fallback: 5h + 30s
    if [ -n "${FIVE_HOUR_RESETS_AT:-}" ]; then
      RESET_EPOCH=$(_iso_to_epoch "$FIVE_HOUR_RESETS_AT")
      NOW=$(date +%s)
      SLEEP_SECS=$(( RESET_EPOCH - NOW + 30 ))
      [ "$SLEEP_SECS" -lt 60 ] && SLEEP_SECS=60
    fi
    printf '[%s] Sleeping %ds until reset\n' "$(date -u +%FT%TZ)" "$SLEEP_SECS"
    sleep "$SLEEP_SECS"

    # Attempt claude --continue
    TASK=""
    [ -f "$TASK_FILE" ] && TASK=$(cat "$TASK_FILE")
    PROMPT="Continue the previous task: ${TASK:-<task unknown — check recent session>}"

    printf '[%s] Resuming: %s\n' "$(date -u +%FT%TZ)" "$PROMPT"
    if claude --continue -p "$PROMPT"; then
      rm -f "$TASK_FILE" "$PID_FILE"
      printf '[%s] Resume successful\n' "$(date -u +%FT%TZ)"
    else
      printf '[%s] Resume failed (exit %s), retrying in 5 min\n' "$(date -u +%FT%TZ)" "$?"
      sleep 300
      if claude --continue -p "$PROMPT"; then
        rm -f "$TASK_FILE" "$PID_FILE"
        printf '[%s] Retry succeeded\n' "$(date -u +%FT%TZ)"
      else
        printf '[%s] Both attempts failed. Run manually: claude --continue\n' "$(date -u +%FT%TZ)"
        rm -f "$PID_FILE"
      fi
    fi
    ;;

  *)
    echo "Usage: ax-resume-watcher.sh --trigger | --watch PROJECT_ROOT" >&2
    exit 1
    ;;
esac
