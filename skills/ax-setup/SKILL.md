---
name: ax-setup
version: 1.15.0
description: |
  Post-install setup for AX plugin. Fully automatic — no manual edits needed.
  Run once after /plugin install ax-claude.
allowed-tools:
  - Bash
  - Read
---

# /ax-setup — AX Post-Install Setup

Run once after installing the AX plugin. Everything is automated.

## Step 1: Resolve plugin root

`$CLAUDE_PLUGIN_ROOT` may be empty when run as a skill. Detect the real path, preferring the active marketplace checkout and then the newest cache entry:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/adapters/ax-ingest.sh" ]; then
  for P in \
    "$HOME/.claude/plugins/marketplaces/ax-claude" \
    $(ls -d "$HOME/.claude/plugins/cache/ax-claude/ax-claude/"* 2>/dev/null | sort -V -r) \
    "$HOME/.ax"; do
    [ -f "$P/adapters/ax-ingest.sh" ] && PLUGIN_ROOT="$P" && break
  done
fi

if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/adapters/ax-ingest.sh" ]; then
  echo "ERROR: AX plugin root not found."
  echo "Run: /plugin install ax-claude"
  exit 1
fi

PLUGIN_BIN="$PLUGIN_ROOT/bin"
echo "PLUGIN_ROOT=$PLUGIN_ROOT"
```

## Step 2: pyyaml + permissions

```bash
# pyyaml
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" 2>/dev/null; then
    echo "pyyaml: OK"
  else
    pip3 install pyyaml --quiet 2>/dev/null \
      || python3 -m pip install pyyaml --quiet 2>/dev/null \
      && echo "pyyaml: installed" \
      || echo "pyyaml: install failed — /ax routing will use manual fallback"
  fi
else
  echo "pyyaml: skipped (python3 not found)"
fi

# permissions
find "$PLUGIN_ROOT/adapters" -name "*.sh" -exec chmod +x {} \;
chmod +x "$PLUGIN_BIN/ax" 2>/dev/null || true
echo "permissions: OK"
```

## Step 3: Auto-configure PATH

Do NOT ask the user to edit their rc file. Append automatically.

```bash
# Detect shell rc file
if [ -n "$ZSH_VERSION" ] || [ "$(basename "${SHELL:-bash}")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
else
  RC_FILE="$HOME/.bashrc"
fi

PATH_LINE="export PATH=\"$PLUGIN_BIN:\$PATH\""

if grep -qF "$PLUGIN_BIN" "$RC_FILE" 2>/dev/null; then
  echo "PATH: already in $RC_FILE"
else
  {
    echo ""
    echo "# AX — Personal Agent Control Plane"
    echo "$PATH_LINE"
  } >> "$RC_FILE"
  echo "PATH: added to $RC_FILE"
fi

# Activate in current session immediately
export PATH="$PLUGIN_BIN:$PATH"
echo "PATH: active in current session"
```

## Step 4: Initialize current project

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [ -f "$PROJECT_ROOT/.ax/config.yaml" ]; then
  echo "ax init: already done for $(basename "$PROJECT_ROOT")"
else
  "$PLUGIN_BIN/ax" init
fi
```

## Step 5: Scan for deprecated command stubs

Scan all installed plugin `commands/` directories for deprecated stubs. Write a skip rule to `~/.claude/CLAUDE.md` if not already present, so Claude never invokes them.

```bash
python3 << 'PYEOF'
import os, glob, re

# Scan for deprecated command stubs across all installed plugins
deprecated = []
for f in glob.glob(os.path.expanduser("~/.claude/plugins/cache/*/*/commands/*.md")):
    try:
        with open(f) as fh:
            content = fh.read()
    except Exception:
        continue
    if re.search(r'description:\s*["\']?Deprecated', content, re.IGNORECASE):
        plugin = f.split(os.sep)[-4]  # e.g. superpowers
        cmd = os.path.splitext(os.path.basename(f))[0]
        repl_m = re.search(r'use (?:the )?([a-z][a-z0-9:_-]+)', content, re.IGNORECASE)
        replacement = repl_m.group(1) if repl_m else "?"
        deprecated.append((plugin, cmd, replacement))

if deprecated:
    print(f"Deprecated command stubs found ({len(deprecated)}):")
    for plugin, cmd, replacement in deprecated:
        print(f"  /{cmd}  →  use /{replacement}")
else:
    print("No deprecated command stubs found.")

# Write skip rule to global CLAUDE.md if missing
claude_md = os.path.expanduser("~/.claude/CLAUDE.md")
rule = "## Skip Deprecated Skills"
if os.path.exists(claude_md):
    with open(claude_md) as fh:
        existing = fh.read()
    if rule not in existing:
        with open(claude_md, "a") as fh:
            fh.write('\n## Skip Deprecated Skills\nNever invoke skills or commands whose description starts with "Deprecated".\n')
        print("CLAUDE.md: added 'Skip Deprecated Skills' rule")
    else:
        print("CLAUDE.md: skip rule already present")
else:
    print("CLAUDE.md: not found — skipping rule write")
PYEOF
```

## Step 6: Print summary

Output a clean completion message:

```
=== AX setup complete ===
  Plugin root : {resolved PLUGIN_ROOT}
  PATH        : {RC_FILE} — updated
  Project     : {PROJECT_ROOT} — initialized

Run /ax to start. To init another project: cd <dir> && ax init
```

Only show failures if any step did not succeed.

## Notes

- SessionEnd hook auto-registers via `hooks/hooks.json` — no `settings.json` edit needed
- `/ax` skill auto-loads from `skills/ax/` — no symlink needed
- Project data lives in `<project>/.ax/` — never deleted on plugin update
