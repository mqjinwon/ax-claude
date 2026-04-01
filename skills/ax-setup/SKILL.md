---
name: ax-setup
version: 1.0.0
description: |
  Post-install setup for AX plugin.
  Run after /plugin install ax-claude to complete configuration.
allowed-tools:
  - Bash
  - Read
---

# /ax-setup — AX Post-Install Setup

Run this after installing the AX plugin:

```
/plugin marketplace add https://github.com/mqjinwon/ax-claude
/plugin install ax-claude
/ax-setup
```

## Step 1: Verify plugin root

```bash
echo "PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"
[ -f "$CLAUDE_PLUGIN_ROOT/adapters/ax-ingest.sh" ] && echo "adapter: OK" || echo "adapter: MISSING"
[ -f "$CLAUDE_PLUGIN_ROOT/skills/ax/SKILL.md" ]   && echo "skill: OK"   || echo "skill: MISSING"
```

If anything is MISSING, tell the user to reinstall: `/plugin install ax-claude`

## Step 2: Install pyyaml (for /ax routing)

```bash
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" 2>/dev/null; then
    echo "pyyaml: already installed"
  else
    pip3 install pyyaml --quiet 2>/dev/null \
      || python3 -m pip install pyyaml --quiet 2>/dev/null \
      || echo "pyyaml install failed — /ax routing will use fallback"
  fi
fi
```

## Step 3: Make adapters executable

```bash
find "$CLAUDE_PLUGIN_ROOT/adapters" -name "*.sh" -exec chmod +x {} \;
chmod +x "$CLAUDE_PLUGIN_ROOT/bin/ax" 2>/dev/null || true
echo "permissions: OK"
```

## Step 4: PATH setup

Tell the user to add `ax` CLI to PATH by adding this to `~/.bashrc` or `~/.zshrc`:

```bash
PLUGIN_BIN="$CLAUDE_PLUGIN_ROOT/bin"
echo "export PATH=\"$PLUGIN_BIN:\$PATH\""
```

Show the exact line to add, with the resolved path. Remind the user to run `source ~/.bashrc` after adding.

## Step 5: Initialize first project

Tell the user:
```
Setup complete! Now initialize AX for your current project:

  cd ~/your-project
  ax init

Then at the start of each Claude session, run /ax to resume context.
```

## Notes

- SessionEnd hook is auto-registered by the plugin system (no manual settings.json edit needed)
- /ax skill is auto-loaded from the plugin's skills/ directory
- Project data lives in <project>/.ax/ — never deleted on plugin update
