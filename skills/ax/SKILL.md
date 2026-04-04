---
name: ax
version: 1.8.0
description: |
  AX Personal Agent Control Plane.
  /ax          → resume: show session context from MEMORY.md
  /ax <task>   → route: recommend the canonical skill for this task
  /ax learn    → show full skill guide (hierarchy + routing categories)
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
# Resolve PLUGIN_ROOT, preferring the active install over stale cache hits.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/lib/ax-utils.sh" ]; then
  for P in \
    "$HOME/.claude/plugins/marketplaces/ax-claude" \
    $(ls -d "$HOME/.claude/plugins/cache/ax-claude/ax-claude/"* 2>/dev/null | sort -V -r) \
    "$HOME/.ax"; do
    [ -f "$P/lib/ax-utils.sh" ] && PLUGIN_ROOT="$P" && break
  done
fi
PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
ROUTING="$PLUGIN_ROOT/routing/skill-routing.yaml"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
echo "PROJECT=$PROJECT_NAME"
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "MEMORY_EXISTS=$([ -f "$MEMORY" ] && echo yes || echo no)"
echo "ROUTING_EXISTS=$([ -f "$ROUTING" ] && echo yes || echo no)"
echo "RESEARCH_NOTES_EXISTS=$([ -f "$PROJECT_ROOT/.ax/memory/research-notes.md" ] && echo yes || echo no)"
echo "EXPERIMENT_LOG_EXISTS=$([ -f "$PROJECT_ROOT/.ax/memory/experiment-log.md" ] && echo yes || echo no)"
echo "DECISIONS_EXISTS=$([ -f "$PROJECT_ROOT/.ax/memory/decisions.md" ] && echo yes || echo no)"
```

If `MEMORY_EXISTS=no`: tell user "This project is not ax-initialized. Run `ax init` first." and stop.

If `MEMORY_EXISTS=yes`: read the full content of `$MEMORY`.
If `ROUTING_EXISTS=yes`: read `$ROUTING`.
If `RESEARCH_NOTES_EXISTS=yes`: store the path `$PROJECT_ROOT/.ax/memory/research-notes.md` as `$RESEARCH_NOTES`.
If `EXPERIMENT_LOG_EXISTS=yes`: store the path `$PROJECT_ROOT/.ax/memory/experiment-log.md` as `$EXPERIMENT_LOG`.
If `DECISIONS_EXISTS=yes`: store the path `$PROJECT_ROOT/.ax/memory/decisions.md` as `$DECISIONS`.

---

## Mode Detection

Determine mode from the user's input AFTER the `/ax` command:

| Input | Mode |
|-------|------|
| (nothing) or `resume` | Resume Mode |
| exactly `learn` (no args) | Guide Mode |
| starts with `learn ` | Learn Mode |
| anything else | Routing Mode |

---

## Resume Mode

Show a structured context summary. Extract sections from MEMORY.md using bash:

```bash
source "$PLUGIN_ROOT/lib/ax-utils.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
echo "=== ACTIVE ==="
ax_get_section "$MEMORY" "active-context"
echo "=== OPEN PROBLEMS ==="
ax_get_section "$MEMORY" "open-problems"
echo "=== RECENT HISTORY ==="
ax_get_section "$MEMORY" "session-history" | head -20
echo "=== RESEARCH NOTES ==="
[ -f "$PROJECT_ROOT/.ax/memory/research-notes.md" ] && \
  ax_get_section "$PROJECT_ROOT/.ax/memory/research-notes.md" "research-notes" | head -10 || echo "(none)"
echo "=== EXPERIMENT LOG ==="
[ -f "$PROJECT_ROOT/.ax/memory/experiment-log.md" ] && \
  ax_get_section "$PROJECT_ROOT/.ax/memory/experiment-log.md" "experiment-log" | head -10 || echo "(none)"
echo "=== RECENT DECISIONS ==="
[ -f "$PROJECT_ROOT/.ax/memory/decisions.md" ] && \
  ax_get_section "$PROJECT_ROOT/.ax/memory/decisions.md" "decisions" | head -15 || \
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

RESEARCH NOTES (last 3)
{research-notes content, if exists}

EXPERIMENT LOG (last 3)
{experiment-log content, if exists}

RECENT DECISIONS
{decisions, last 2 entries only}
```

End with one-line suggestion: what to do next given the active context.
If active context says a task is in-progress, suggest continuing it.
If everything is done, suggest starting fresh with `/ax <task description>`.

---

## Guide Mode

User ran: `/ax learn` (no arguments).

Run the guide script and output its result:

```bash
if [ -f "$PLUGIN_ROOT/bin/ax-guide.py" ]; then
  python3 "$PLUGIN_ROOT/bin/ax-guide.py" "$PLUGIN_ROOT/routing/skill-routing.yaml"
else
  echo "ax-guide.py not found — run: /plugin install ax-claude"
fi
```

If Python is unavailable or the script is missing, read `$ROUTING` (already loaded in Preamble) and manually summarize the categories.

After the script output, append the static hierarchy section:

```
────────────────────────────────────────────────────────────
스킬 계층 구조

[Level 1] 전체 파이프라인
  research-pipeline    아이디어 발굴 → 실험 → 논문 제출까지

[Level 2] Workflow Orchestrators
  idea-discovery-robot   Workflow 1: 로보틱스 아이디어 발굴
  research-refine-pipeline  research-refine + experiment-plan
  experiment-bridge      Workflow 1.5: 아이디어 → 실험 브릿지
  auto-review-loop       Workflow 2: 실험 → 논문 반복 개선
  paper-writing          Workflow 3: 보고서 → PDF 전체
  rebuttal               Workflow 4: 리뷰어 반박

[Level 3] 직접 호출 가능한 단위 스킬
  문헌:   research-lit · arxiv · semantic-scholar
  아이디어: idea-creator · novelty-check · research-refine
  실험설계: experiment-plan · ablation-planner · dse-loop
  실험실행: run-experiment · monitor-experiment · training-check
  결과분석: analyze-results · result-to-claim
  논문작성: paper-plan · paper-write · paper-figure · paper-compile
           paper-slides · paper-poster · humanizer

────────────────────────────────────────────────────────────
문서화 파이프라인

  논문 완성 후
    → /paper-slides   학회 발표 슬라이드 (Beamer + PPTX)
    → /paper-poster   학회 포스터 (A0/A1)
    → /humanizer      최종 AI 흔적 제거

  기술 문서 / 다이어그램
    → /mermaid-diagram  시스템 아키텍처

  연구비 신청
    → /grant-proposal  (KAKENHI · NSF · NRF)
```

---

## Routing Mode

The user described a task. Find the best canonical skill.

### Step 1: Keyword match (deterministic)

```bash
source "$PLUGIN_ROOT/lib/ax-utils.sh"
_OVERRIDES=$(ax_get_section "$MEMORY" "routing-overrides" 2>/dev/null || true)
_OVERRIDE_MATCH=""

while IFS= read -r _OV_LINE; do
  case "$_OV_LINE" in
    "- \`"*)
      _OV_PAT=$(printf '%s' "$_OV_LINE" | sed "s/^- \`//;s/\` →.*//")
      _OV_SKILL=$(printf '%s' "$_OV_LINE" | sed "s/.*→ \`//;s/\`.*//")
      if [ -n "$_OV_PAT" ] && printf '%s' "<user's full input>" | grep -qiF "$_OV_PAT"; then
        _OVERRIDE_MATCH="$_OV_SKILL"
        break
      fi
      ;;
  esac
done <<< "$_OVERRIDES"

if [ -n "$_OVERRIDE_MATCH" ]; then
  echo "MATCH=routing-override (project-local)"
  echo "CANONICAL=$_OVERRIDE_MATCH"
  echo "MODE=canonical"
elif [ -f "$PLUGIN_ROOT/bin/ax-route.py" ]; then
  python3 "$PLUGIN_ROOT/bin/ax-route.py" "<user's full input>" "$PLUGIN_ROOT/routing/skill-routing.yaml"
else
  echo "MATCH="
  echo "ax-route.py not found — run: /plugin install ax-claude"
fi
```

Replace `<user's full input>` with the actual input text before running.
If `_OVERRIDE_MATCH` is non-empty (routing-override hit), skip Step 2 and proceed directly to Step 3 output.

Output format (one per line, only present fields):
```
MATCH=<category>
CANONICAL=<skill>
MODE=orchestrator|canonical
ORCHESTRATOR=<skill>   # only when MODE=canonical and orchestrator exists
```

If Python is unavailable, do the keyword check mentally using the routing YAML you read.

### Step 2: Semantic fallback (if no keyword match or MATCH is empty)

Use your judgment:
- Is this about bugs/errors? → debugging
- Is this about writing/planning code? → planning
- Is this about checking code? → code_review
- Is this about implementing everything? → execution
- Is this about papers/writing? → research_paper
- Is this about finding papers? → research_lit
- Is this about running experiments? → research_experiment

### Step 3: Output the recommendation

If `MODE=orchestrator`:
```
→ /{orchestrator}  (전체 파이프라인)

Why: {one sentence — which trigger matched and why this skill fits}
```

If `MODE=canonical` with orchestrator available:
```
→ /{canonical}  (단계별 실행)
   전체 파이프라인이 필요하면: /{orchestrator}

Why: {one sentence — which trigger matched and why this skill fits}
```

If canonical only:
```
→ /{canonical}

Why: {one sentence — which trigger matched and why this skill fits}
Aliases: {other skills that could also work, if any}
```

**IMPORTANT**: Do NOT invoke the skill automatically. Just recommend it.
The user decides which skill to run.

### Step 4: Load topic file if relevant

Based on the matched category, conditionally read the relevant topic file:

| Category | Topic file to read |
|----------|--------------------|
| `research_lit`, `research_ideation`, `research_paper`, `research_full_pipeline` | `$RESEARCH_NOTES` (if exists) |
| `research_experiment`, `result_analysis`, `gpu_compute`, `design_space` | `$EXPERIMENT_LOG` (if exists) |
| `planning`, `debugging`, `code_review` | `$DECISIONS` (if exists) |

Read the topic file now using the Read tool, and include a brief summary (last 5 entries) in your routing response under:

```
CONTEXT FROM {TOPIC_FILE_NAME}
{brief summary}
```

If the topic file is empty or doesn't exist, skip silently.

---

## Learn Mode

User ran: `/ax learn <insight text>`

Extract everything after `learn ` as the insight.

### Step 1: Write insight to decisions file

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/lib/ax-utils.sh" ]; then
  for _P in \
    $(ls -d "$HOME/.claude/plugins/cache/ax-claude/ax-claude/"* 2>/dev/null | sort -V -r | head -1) \
    "$HOME/.claude/plugins/marketplaces/ax-claude" \
    "$HOME/.ax"; do
    [ -f "$_P/lib/ax-utils.sh" ] && PLUGIN_ROOT="$_P" && break
  done
fi
PLUGIN_ROOT="${PLUGIN_ROOT:-$HOME/.ax}"
source "$PLUGIN_ROOT/lib/ax-utils.sh"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
# Use decisions.md if split memory is enabled
if [ -f "$PROJECT_ROOT/.ax/memory/decisions.md" ]; then
  MEMORY="$PROJECT_ROOT/.ax/memory/decisions.md"
fi
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

# Route override detection
ROUTE_PATTERN=""; ROUTE_SKILL=""
case "<INSERT_INSIGHT_HERE>" in
  route:*)
    _RB="<INSERT_INSIGHT_HERE>"
    _RB="${_RB#route:}"
    _RB="${_RB# }"
    if printf '%s' "$_RB" | grep -q '→'; then
      ROUTE_PATTERN="${_RB%%→*}"
      ROUTE_SKILL="${_RB##*→}"
    elif printf '%s' "$_RB" | grep -q '->'; then
      ROUTE_PATTERN="${_RB%%->*}"
      ROUTE_SKILL="${_RB##*->}"
    fi
    ROUTE_PATTERN=$(printf '%s' "$ROUTE_PATTERN" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    ROUTE_SKILL=$(printf '%s' "$ROUTE_SKILL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    ;;
esac
if [ -n "$ROUTE_PATTERN" ] && [ -n "$ROUTE_SKILL" ]; then
  MAIN_MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
  if grep -q 'BEGIN:routing-overrides' "$MAIN_MEMORY" 2>/dev/null; then
    if grep -qF "- \`$ROUTE_PATTERN\`" "$MAIN_MEMORY" 2>/dev/null; then
      echo "Routing override for '$ROUTE_PATTERN' already exists — skipping duplicate."
    else
      OVERRIDE_FILE=$(mktemp)
      ax_get_section "$MAIN_MEMORY" "routing-overrides" \
        | grep -v '^_No overrides' > "$OVERRIDE_FILE" || true
      printf '- `%s` → `%s`\n' "$ROUTE_PATTERN" "$ROUTE_SKILL" >> "$OVERRIDE_FILE"
      ax_replace_section "$MAIN_MEMORY" "routing-overrides" "$OVERRIDE_FILE"
      rm -f "$OVERRIDE_FILE"
      echo "Routing override added: '$ROUTE_PATTERN' → '$ROUTE_SKILL'"
    fi
  else
    echo "Warning: routing-overrides section not found in $MAIN_MEMORY. Run 'ax init' to upgrade."
  fi
fi
```

Replace `<INSERT_INSIGHT_HERE>` with the actual insight text before running (escape any special chars with `printf '%s'`).

### Step 2: Confirm

Reply: "Recorded to `$MEMORY` → decisions section."
Show the recorded entry so the user can verify it looks right.
If the insight was a `route:` override, also confirm: "Routing override recorded to `$MAIN_MEMORY` → routing-overrides section."
