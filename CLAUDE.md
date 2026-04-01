# ax-claude — Claude Code Instructions

## Versioning
On every change, update BOTH files to keep them in sync:
- `VERSION`
- `.claude-plugin/plugin.json` → `"version"` field

Scheme:
- Significant changes (new features, behavior changes): bump minor → `0.x.0`
- Small fixes / typos / docs: bump patch → `0.0.x`

## GitHub Workflow
Flow: issue → worktree + branch → implement → PR → squash & merge
NEVER commit or push directly to main/master — no exceptions.
PR title: `[type] English title` (feat/fix/chore/docs/refactor)
PR body: Korean, technical terms in English
