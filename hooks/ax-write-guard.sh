#!/usr/bin/env bash
# ax-write-guard.sh — PreToolUse hook
# Blocks Write/Edit tool calls targeting .ax/memory/ files.
# ax-claude's own operations use shell commands (Bash tool / ax-ingest.sh),
# so they are unaffected. Only direct Write/Edit tool calls are intercepted.

INPUT=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
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
