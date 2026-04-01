---
name: ax
version: 1.0.0
description: |
  AX Personal Agent Control Plane.
  /ax          → resume: show session context from MEMORY.md
  /ax <task>   → route: recommend the canonical skill for this task
  /ax learn X  → record insight X to MEMORY.md decisions section
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# /ax — AX Personal Agent Control Plane

## Preamble

Run this bash block first to load project context:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
# Resolve PLUGIN_ROOT: git-clone install (~/.ax) → ax in PATH → plugin cache
if [ -f "$HOME/.ax/lib/ax-utils.sh" ]; then
  PLUGIN_ROOT="$HOME/.ax"
elif AX_BIN=$(command -v ax 2>/dev/null) && [ -n "$AX_BIN" ]; then
  _AX_REAL="$(readlink -f "$AX_BIN" 2>/dev/null || echo "$AX_BIN")"
  PLUGIN_ROOT="$(cd "$(dirname "$_AX_REAL")/.." && pwd)"
else
  _CACHE_HIT=$(find "$HOME/.claude/plugins" -name "ax-utils.sh" 2>/dev/null | head -1)
  PLUGIN_ROOT="${_CACHE_HIT%/lib/ax-utils.sh}"
  PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
fi
ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
echo "PROJECT=$PROJECT_NAME"
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "MEMORY_EXISTS=$([ -f "$MEMORY" ] && echo yes || echo no)"
echo "ROUTING_EXISTS=$([ -f "$ROUTING" ] && echo yes || echo no)"
```

If `MEMORY_EXISTS=no`: tell user "This project is not ax-initialized. Run `ax init` first." and stop.

If `MEMORY_EXISTS=yes`: read the full content of `$MEMORY`.
If `ROUTING_EXISTS=yes`: read `$ROUTING`.

---

## Mode Detection

Determine mode from the user's input AFTER the `/ax` command:

| Input | Mode |
|-------|------|
| (nothing) or `resume` | Resume Mode |
| starts with `learn ` | Learn Mode |
| anything else | Routing Mode |

---

## Resume Mode

Show a structured context summary. Extract sections from MEMORY.md using bash:

```bash
# Resolve PLUGIN_ROOT: git-clone install (~/.ax) → ax in PATH → plugin cache
if [ -f "$HOME/.ax/lib/ax-utils.sh" ]; then
  PLUGIN_ROOT="$HOME/.ax"
elif AX_BIN=$(command -v ax 2>/dev/null) && [ -n "$AX_BIN" ]; then
  _AX_REAL="$(readlink -f "$AX_BIN" 2>/dev/null || echo "$AX_BIN")"
  PLUGIN_ROOT="$(cd "$(dirname "$_AX_REAL")/.." && pwd)"
else
  _CACHE_HIT=$(find "$HOME/.claude/plugins" -name "ax-utils.sh" 2>/dev/null | head -1)
  PLUGIN_ROOT="${_CACHE_HIT%/lib/ax-utils.sh}"
  PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
fi
source "$PLUGIN_ROOT/lib/ax-utils.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
echo "=== ACTIVE ==="
ax_get_section "$MEMORY" "active-context"
echo "=== OPEN PROBLEMS ==="
ax_get_section "$MEMORY" "open-problems"
echo "=== RECENT HISTORY ==="
ax_get_section "$MEMORY" "session-history" | head -20
echo "=== RECENT DECISIONS ==="
ax_get_section "$MEMORY" "decisions" | head -15
```

Format the output for the user:

```
=== AX Resume: {PROJECT_NAME} ===

ACTIVE CONTEXT
{active-context content}

OPEN PROBLEMS
{open-problems content — if empty, say "None recorded"}

RECENT SESSIONS
{session-history, last 3-5 bullet entries only}

RECENT DECISIONS
{decisions, last 2 entries only}
```

End with one-line suggestion: what to do next given the active context.
If active context says a task is in-progress, suggest continuing it.
If everything is done, suggest starting fresh with `/ax <task description>`.

---

## Routing Mode

The user described a task. Find the best canonical skill.

### Step 1: Keyword match (deterministic)

Run this bash to check triggers from skill-routing.yaml:

```bash
# Resolve PLUGIN_ROOT: git-clone install (~/.ax) → ax in PATH → plugin cache
if [ -f "$HOME/.ax/lib/ax-utils.sh" ]; then
  PLUGIN_ROOT="$HOME/.ax"
elif AX_BIN=$(command -v ax 2>/dev/null) && [ -n "$AX_BIN" ]; then
  _AX_REAL="$(readlink -f "$AX_BIN" 2>/dev/null || echo "$AX_BIN")"
  PLUGIN_ROOT="$(cd "$(dirname "$_AX_REAL")/.." && pwd)"
else
  _CACHE_HIT=$(find "$HOME/.claude/plugins" -name "ax-utils.sh" 2>/dev/null | head -1)
  PLUGIN_ROOT="${_CACHE_HIT%/lib/ax-utils.sh}"
  PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
fi
export ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"
INPUT="<user's full input, lowercased>"

# Extract trigger lists per category and test against input
# Output: MATCH=<category> if found, MATCH= if not found
python3 - << 'PYEOF'
import yaml, sys, os

ROUTING_PATH = os.environ.get("ROUTING") or os.path.expanduser("~/.ax/routing/skill-routing.yaml")
with open(ROUTING_PATH) as f:
    data = yaml.safe_load(f)

inp = """<user input lowercased>"""

# Check longer/more-specific triggers first (sort by length desc)
for cat, info in data.get("categories", {}).items():
    triggers = info.get("trigger", [])
    triggers_sorted = sorted(triggers, key=len, reverse=True)
    for t in triggers_sorted:
        if t.lower() in inp.lower():
            print(f"MATCH={cat}")
            print(f"CANONICAL={info['canonical']}")
            sys.exit(0)

print("MATCH=")
PYEOF
```

If Python is unavailable, do the keyword check mentally using the routing YAML you read.

### Step 2: Semantic fallback (if no keyword match)

If Step 1 found no match, use your judgment:
- Is this about bugs/errors? → debugging
- Is this about writing/planning code? → planning
- Is this about checking code? → code_review
- Is this about implementing everything? → execution
- Is this about papers/writing? → research_paper
- Is this about finding papers? → research_lit
- Is this about running experiments? → research_experiment

### Step 3: Output the recommendation

```
→ /{canonical-skill}

Why: {one sentence — which trigger matched and why this skill fits}
Aliases: {other skills that could also work, if any}
```

**IMPORTANT**: Do NOT invoke the skill automatically. Just recommend it.
The user decides which skill to run.

---

## Learn Mode

User ran: `/ax learn <insight text>`

Extract everything after `learn ` as the insight.

### Step 1: Write insight to MEMORY.md

```bash
# Resolve PLUGIN_ROOT: git-clone install (~/.ax) → ax in PATH → plugin cache
if [ -f "$HOME/.ax/lib/ax-utils.sh" ]; then
  PLUGIN_ROOT="$HOME/.ax"
elif AX_BIN=$(command -v ax 2>/dev/null) && [ -n "$AX_BIN" ]; then
  _AX_REAL="$(readlink -f "$AX_BIN" 2>/dev/null || echo "$AX_BIN")"
  PLUGIN_ROOT="$(cd "$(dirname "$_AX_REAL")/.." && pwd)"
else
  _CACHE_HIT=$(find "$HOME/.claude/plugins" -name "ax-utils.sh" 2>/dev/null | head -1)
  PLUGIN_ROOT="${_CACHE_HIT%/lib/ax-utils.sh}"
  PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
fi
source "$PLUGIN_ROOT/lib/ax-utils.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
DATE=$(date +%Y-%m-%d)
TS=$(date +%Y%m%d%H%M)
ENTRY_ID="${TS}-manual"

# Write insight to temp file then prepend to decisions section
INSIGHT_FILE=$(mktemp)
printf '<!-- entry:%s -->\n' "$ENTRY_ID" > "$INSIGHT_FILE"
printf '**%s** (manual): %s\n\n' "$DATE" "<INSERT_INSIGHT_HERE>" >> "$INSIGHT_FILE"

# Append existing decisions (minus placeholder)
ax_get_section "$MEMORY" "decisions" \
  | grep -v '^_No decisions recorded yet' >> "$INSIGHT_FILE" || true

ax_replace_section "$MEMORY" "decisions" "$INSIGHT_FILE"
rm -f "$INSIGHT_FILE"
```

Replace `<INSERT_INSIGHT_HERE>` with the actual insight text before running (escape any special chars with `printf '%s'`).

### Step 2: Confirm

Reply: "Recorded to `$MEMORY` → decisions section."
Show the recorded entry so the user can verify it looks right.
