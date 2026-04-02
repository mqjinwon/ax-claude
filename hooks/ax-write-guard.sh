#!/usr/bin/env bash
# ax-write-guard.sh — PreToolUse hook
# 1. Enforces 5-hour usage rate limit thresholds (warn / pause / block)
# 2. Blocks Write/Edit calls targeting .ax/memory/ (managed by ax-ingest)

INPUT=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve plugin root (works both when invoked by Claude Code and in tests)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Resolve project root from hook cwd → git root
PROJECT_ROOT=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -n "$PROJECT_ROOT" ] && command -v git >/dev/null 2>&1; then
  GIT_ROOT=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_ROOT")
  PROJECT_ROOT="$GIT_ROOT"
fi
: "${PROJECT_ROOT:=$HOME}"

# ── Rate limit check ─────────────────────────────────────────────────────────

_ax_rl_config() {
  local key="$1" default="$2"
  local cfg="$PROJECT_ROOT/.ax/config.yaml"
  [ -f "$cfg" ] || { printf '%s' "$default"; return; }
  python3 - "$cfg" "$key" "$default" << 'PY' 2>/dev/null || printf '%s' "$default"
import sys, re
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
  m = re.search(r'^\s*' + re.escape(key) + r'\s*:\s*(\S+)', open(path).read(), re.M)
  print(int(m.group(1)) if m else int(default))
except Exception: print(default)
PY
}

# Source usage library (safe — exits cleanly if unavailable)
# shellcheck source=../lib/ax-usage.sh
if [ -f "$PLUGIN_ROOT/lib/ax-usage.sh" ]; then
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/lib/ax-usage.sh"
  if ax_get_usage 2>/dev/null && [ -n "${FIVE_HOUR_PERCENT:-}" ]; then
    WARN_AT=$(_ax_rl_config "warn_at"  "80")
    PAUSE_AT=$(_ax_rl_config "pause_at" "90")
    BLOCK_AT=$(_ax_rl_config "block_at" "100")
    PCT="$FIVE_HOUR_PERCENT"

    if [ "$PCT" -ge "$BLOCK_AT" ]; then
      echo "[ax] Usage limit reached (${PCT}%). All tools blocked."
      echo "Auto-resume watcher will restart this session at: ${FIVE_HOUR_RESETS_AT:-unknown}"
      exit 2
    fi

    if [ "$PCT" -ge "$PAUSE_AT" ]; then
      case "$TOOL" in
        Write|Edit)
          # Allow Write/Edit so Claude can save the task file
          ;;
        *)
          echo "[ax] Usage at ${PCT}% — pause threshold (${PAUSE_AT}%) reached."
          echo "REQUIRED: Use the Write tool to save your current task to:"
          echo "  ${PROJECT_ROOT}/.ax/resume-task.txt"
          echo "Then stop. Auto-resume will trigger at: ${FIVE_HOUR_RESETS_AT:-unknown}"
          exit 2
          ;;
      esac
    fi

    if [ "$PCT" -ge "$WARN_AT" ]; then
      echo "[ax] Warning: Claude Code usage at ${PCT}% (pause at ${PAUSE_AT}%)."
      echo "Consider: ax queue \"<current task>\" to register for auto-resume."
      # exit 0 — tool proceeds; warning shown to Claude as context
    fi
  fi
fi

# ── Write-guard for .ax/memory/ ──────────────────────────────────────────────
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

if [[ "$FILE_PATH" =~ /\.ax/memory/ ]]; then
  echo "ax-write-guard: blocked direct write to $FILE_PATH"
  echo ""
  echo ".ax/memory/ is managed exclusively by ax-ingest.sh (SessionEnd hook)."
  echo "  • To add a decision/insight  → /ax learn <text>"
  echo "  • To update via shell        → use Bash tool with ax_replace_section"
  echo "  • For auto-memory            → write to ~/.claude/projects/<hash>/memory/"
  exit 2
fi

exit 0
