# ax-claude — Claude Code Instructions

## GitHub Workflow
Flow: issue → worktree + branch → implement → PR → squash & merge → cleanup
NEVER commit or push directly to main — no exceptions.

After squash & merge, always run cleanup:
```bash
git worktree remove ~/<worktree-dir>
git fetch origin && git branch -d <branch>
```

## Versioning

**MANDATORY**: Version bump is part of every implementation. Do it BEFORE creating the PR — never as an afterthought after being reminded.

On every change, update ALL three files to keep them in sync:
- `VERSION`
- `.claude-plugin/plugin.json` → `"version"` field
- `.claude-plugin/marketplace.json` → top-level `"version"` and `plugins[0].version`

Scheme:
- Significant changes (new features, behavior changes): bump minor → `0.x.0`
- Small fixes / typos / docs: bump patch → `0.0.x`

**README**: After every feature addition, update `README.md` with a user-facing usage guide — not internal implementation details.

Pre-PR checklist (verify before `gh pr create`):
- [ ] VERSION bumped
- [ ] `.claude-plugin/plugin.json` version matches
- [ ] `.claude-plugin/marketplace.json` version matches (both occurrences)
- [ ] `README.md` updated if new feature added
