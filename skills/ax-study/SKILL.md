---
name: ax-study
version: 1.18.0
description: |
  /ax-study <pdf|url>          문서/논문 학습 시작
  /ax-study quiz [N]           배운 내용 퀴즈 (Active Recall, 기본 5문제)
  /ax-study feynman <개념>     이해도 검증 (멀티턴 소크라테스 대화)
  /ax-study concept <개념>     개념 심화 학습
  /ax-study explore <주제>     후속 자료 탐색
  /ax-study audio              오디오 요약 생성
  또는 자연어: "이해 안가" → feynman 자동, "퀴즈 내줘" → quiz 자동
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# /ax-study — Document Study Skill

## Preamble

Run this bash block first to load project and study context:

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
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

MEMORY="$PROJECT_ROOT/.ax/memory/MEMORY.md"
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"

# Bootstrap study-notes.md from template if not exists
ax_ensure_topic_file "$PROJECT_ROOT" "study-notes" "$PLUGIN_ROOT/templates/STUDY_NOTES.template.md"

echo "PROJECT=$(basename "$PROJECT_ROOT")"
echo "STUDY_NOTES_EXISTS=$([ -f "$STUDY_NOTES" ] && echo yes || echo no)"

# Read CLAUDE.md for optional NLM notebook mapping
if [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
  NLM_SECTION=$(grep -A 20 "NotebookLM\|notebooklm\|Notebook ID" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null | head -20 || true)
  [ -n "$NLM_SECTION" ] && echo "NLM_CONFIG_EXISTS=yes" || echo "NLM_CONFIG_EXISTS=no"
else
  echo "NLM_CONFIG_EXISTS=no"
fi
```

After running:
- Read `$STUDY_NOTES` full content
- If `NLM_CONFIG_EXISTS=yes`: extract notebook ID mapping from CLAUDE.md for use in subsequent steps
- Store `PROJECT_ROOT` and `STUDY_NOTES` for later bash blocks

---

## Mode Detection

Determine mode from the user's input AFTER the `/ax-study` command.
Apply rules in priority order — first match wins.

| 우선순위 | 입력 패턴 | 모드 |
|---|---|---|
| 1 | URL(`https?://`) 또는 파일 경로(`.pdf`, `.md`, `~/`, `/home/`) | Init Mode |
| 2 | `quiz` 또는 `quiz <숫자>` | Quiz Mode |
| 3 | `feynman <개념명>` | Feynman Mode |
| 4 | `concept <name>` | Concept Mode |
| 5 | `explore <topic>` | Explore Mode |
| 6 | `audio` | Audio Mode |
| 7 | 자연어 퀴즈 의도: "테스트", "퀴즈", "문제 내줘", "맞혀볼게", "확인해줘", "시험", "test me", "quiz me", "check my understanding" | Quiz Mode |
| 8 | 자연어 Feynman 의도: "이해가 안 가", "모르겠어", "헷갈려", "다시 설명", "쉽게", "어렵다", "confused", "don't understand", "explain to me" (개념명 있으면 바로 feynman, 없으면 개념명 질문 후 feynman) | Feynman Mode |
| 9 | 자연어 개념: "<명사> 뭐야", "<명사> 알려줘", "<명사> 설명해줘" → concept <명사> 로 변환 | Concept Mode |
| 10 | (아무것도 없음) | Resume Mode |

---

## Resume Mode

**Trigger**: `/ax-study` (no arguments)

Read study-notes.md and show progress summary:

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
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"

echo "=== ACTIVE DOCUMENT ==="
ax_get_section "$STUDY_NOTES" "active-document"
echo "=== STUDY QUEUE ==="
ax_get_section "$STUDY_NOTES" "study-queue"
echo "=== RECENT CONCEPTS ==="
ax_get_section "$STUDY_NOTES" "concept-notes" | tail -20
echo "=== OPEN QUESTIONS ==="
ax_get_section "$STUDY_NOTES" "open-questions"
```

If active-document is empty (`_No document loaded yet.`):
```
No active study. Run /ax-study <pdf-path-or-url> to start.
```

Otherwise, format the output:

```
=== AX Study: Resume ===

Document: {title from active-document}
Notebook: {notebook_id}
Progress: {count of [x] items}/{total items} sections

Next up: {first [ ] item in study-queue, or item tagged "next"}
  → /ax-study concept "{next item topic}" to dive in

Recent concepts (last 3):
- {concept entry summary}

Open questions ({count of [ ] items}):
- {question}

Commands:
  /ax-study concept <name>  — 개념 심화 학습
  /ax-study explore <topic> — 후속 연구 탐색
  /ax-study audio           — 오디오 요약 생성
  /notebooklm-study         — quiz, report 등 NLM 직접 활용
```

[active-document 있을 때 → Hint Footer: "active-document 있을 때" 형식 사용]
[active-document 없을 때 → Hint Footer: "active-document 없을 때" 형식 사용]

---

## Init Mode

**Trigger**: `/ax-study <pdf-path-or-url>`

### Step 1: Resolve notebook

Check CLAUDE.md for notebook ID mapping (already loaded in Preamble).

If no mapping found, use `notebook_list` MCP tool to search for a notebook matching the project name or document name. If no match, create a new notebook with `notebook_create`.

### Step 2: Add source

Call `source_add` MCP tool with the pdf path or URL:
- For local PDF: use `source_type="file"`, `file_path=<absolute path>`
- For URL: use `source_type="url"`, `url=<url>`

### Step 3: Describe structure

Call `notebook_describe` MCP tool to get an AI-generated summary and list of topics/sections.

### Step 4: Build study roadmap

From the `notebook_describe` output, generate a prioritized learning sequence:
1. Parse chapter/section structure
2. Identify prerequisite topics (mark as "background needed")
3. Create ordered queue items

### Step 5: Initialize study-notes.md

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
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"

# Write active-document section
DOC_FILE=$(mktemp)
cat > "$DOC_FILE" << 'DOCEOF'
- **Title**: <INSERT_TITLE>
- **Notebook ID**: <INSERT_NOTEBOOK_ID>
- **Source**: <INSERT_SOURCE>
- **Structure**: <INSERT_SECTION_COUNT> sections
- **Progress**: 0/<INSERT_TOTAL> sections
- **Last studied**: <INSERT_DATE>
DOCEOF
ax_replace_section "$STUDY_NOTES" "active-document" "$DOC_FILE"
rm -f "$DOC_FILE"

# Write study-queue section
QUEUE_FILE=$(mktemp)
# INSERT_QUEUE_ITEMS — one "- [ ] {Section title}" per line
ax_replace_section "$STUDY_NOTES" "study-queue" "$QUEUE_FILE"
rm -f "$QUEUE_FILE"
```

Replace all `<INSERT_*>` placeholders with actual values before running.

### Output format

```
=== AX Study: Init ===

Document: {title}
Notebook: {notebook_id} ({created|matched|from config})
Structure: {N} sections detected

Study Roadmap:
1. [ ] {Section 1 title}
2. [ ] {Section 2 title}
...

Background topics identified:
- {topic}: /ax-study concept {topic} 로 배경지식 먼저 확인하세요

study-notes.md initialized.
Run /ax-study to resume anytime.
```

[Hint Footer: "active-document 있을 때" 형식 사용]

---

## Concept Mode

**Trigger**: `/ax-study concept <concept-name>`

### Step 1: Read active notebook ID

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
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"
ax_get_section "$STUDY_NOTES" "active-document" | grep "Notebook ID"
```

If no notebook ID found, tell user to run `/ax-study <pdf>` first.

### Step 2: Query NLM

Call `notebook_query` MCP tool:
- `notebook_id`: from active-document
- `query`: `"Explain {concept-name} in detail, including its definition, key insights, and how it relates to other concepts in this document."`

### Step 3: Background knowledge (optional)

If the NLM response references external libraries, frameworks, or foundational concepts not covered in the document:
1. Call `mcp__plugin_context7_context7__resolve-library-id` with the library name
2. Call `mcp__plugin_context7_context7__query-docs` with a focused query
3. Include the result in a `[Background]` section

If context7 MCP is unavailable, skip this step silently.

### Step 4: Synthesize and save

Build a structured concept note:
```markdown
<!-- entry:{YYYYMMDD}-{concept-slug} -->
### {Concept Name}
- **Definition**: {one-sentence definition}
- **Key insight**: {most important thing to remember}
- **Source**: {section reference from document}
- **Related**: {related concepts}
- **Background**: {context7 source if used, else omit}
```

Save to NLM with `note` MCP tool, then update study-notes.md:

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
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"
DATE=$(date +%Y%m%d)
CONCEPT_SLUG="<INSERT_CONCEPT_SLUG>"

NOTES_FILE=$(mktemp)
ax_get_section "$STUDY_NOTES" "concept-notes" \
  | grep -v '^_No concepts recorded yet' > "$NOTES_FILE" || true

cat >> "$NOTES_FILE" << 'NOTEEOF'
<!-- entry:<INSERT_ENTRY_ID> -->
<INSERT_CONCEPT_NOTE>
NOTEEOF

ax_replace_section "$STUDY_NOTES" "concept-notes" "$NOTES_FILE"
rm -f "$NOTES_FILE"
```

Also mark related study-queue items as `[x]` if applicable.

### Output format

```
=== AX Study: Concept — {concept-name} ===

{structured explanation from NLM}

[Background — from context7]
{supplementary library/framework explanation, if applicable}

Saved: concept-notes entry:{entry-id}
NLM note synced.
```

[Hint Footer: "active-document 있을 때" 형식 사용]

---

## Explore Mode

**Trigger**: `/ax-study explore <topic>`

### Step 1: Gather context

Read current active-document and recent concept-notes from study-notes.md to understand the research context.

### Step 2: Recommend skills

Based on the topic and context, recommend the appropriate skill:
- Latest preprints / rapidly evolving area → `/arxiv "{suggested query}"`
- Peer-reviewed venue papers → `/semantic-scholar "{suggested query}"`
- Broad survey needed → `/research-lit "{suggested query}"`

**IMPORTANT**: Do NOT invoke these skills automatically. Only recommend them. The user decides.

### Step 3: Offer NLM research (with confirmation)

Ask the user: "NotebookLM으로 '{topic}' 관련 자료를 자동 탐색할까요? (yes/no)"

If yes: call `research_start` MCP tool with `notebook_id` and `query=topic`, then poll `research_status`. Report found sources and ask if user wants to import them with `research_import`.

### Step 4: Update study-notes.md

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
STUDY_NOTES="$PROJECT_ROOT/.ax/memory/study-notes.md"

# Add to open-questions
QQ_FILE=$(mktemp)
ax_get_section "$STUDY_NOTES" "open-questions" \
  | grep -v '^_No open questions yet' > "$QQ_FILE" || true
printf '- [ ] Explore: %s — needs /arxiv or /semantic-scholar search\n' "<INSERT_TOPIC>" >> "$QQ_FILE"
ax_replace_section "$STUDY_NOTES" "open-questions" "$QQ_FILE"
rm -f "$QQ_FILE"
```

### Output format

```
=== AX Study: Explore — {topic} ===

Context from current study:
{brief summary of relevant concepts already learned}

Recommended:
  → /arxiv "{suggested query}"
  → /semantic-scholar "{suggested query}"

NLM Research: NotebookLM으로 자동 탐색할까요? (yes/no)

Tracked: open-questions에 탐색 항목 추가됨.
```

---

## Audio Mode

**Trigger**: `/ax-study audio`

### Step 1: Validate

Read notebook ID from active-document. If empty, tell user to run `/ax-study <pdf>` first.

### Step 2: Generate audio

Call `studio_create` MCP tool:
- `notebook_id`: from active-document
- `artifact_type`: `"audio"`

### Step 3: Poll status

Call `studio_status` MCP tool every 30 seconds up to 5 times. Show: `오디오 생성 중... (상태: {status})`

### Step 4: Download

On completion, derive the output path:
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
NB_SHORT="<INSERT_NOTEBOOK_SHORT>"  # lowercase, ≤15 chars, meaningful tokens
mkdir -p "$PROJECT_ROOT/nblm/$NB_SHORT"
OUTPUT_PATH="$PROJECT_ROOT/nblm/$NB_SHORT/${NB_SHORT}_audio_overview.mp3"
echo "$OUTPUT_PATH"
```

Call `download_artifact` MCP tool with the output path.

### Output format

```
=== AX Study: Audio ===

Generating audio overview for: {document title}
Studio status: completed

Audio ready: {file_path}
Play with: mpv {file_path}  (or your preferred player)
```

---

## Hint Footer

모든 모드의 응답 마지막에 현재 컨텍스트에 맞는 힌트를 출력한다.

### active-document 있을 때 (기본)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
다음 액션:
  /ax-study quiz               ← 배운 내용 테스트
  /ax-study feynman <개념>     ← 이해도 검증
  /ax-study concept <개념>     ← 개념 심화
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### active-document 없을 때 (초기)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
시작하려면:
  /ax-study <pdf 경로>         ← 로컬 PDF
  /ax-study <url>              ← 웹 문서 / 논문
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Quiz 완료 후

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
결과: {정답}/{총} 정답 | 약점: [{약점 개념 목록}]
다음:
  /ax-study feynman <약점 개념>  ← 약점 집중
  /ax-study concept <약점 개념>  ← 개념 재학습
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

약점 없으면 (전체 정답):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 전체 정답! 다음 단계:
  /ax-study explore <주제>     ← 후속 탐색
  /ax-study audio              ← 오디오 요약
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Feynman 완료 후

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Feynman 통과: {개념명} | 숙달 상태: feynman-passed
다음:
  /ax-study quiz               ← 전체 퀴즈로 확인
  /ax-study explore <주제>     ← 후속 탐색
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Feynman 중단 시:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
약점 기록: {개념명} → weak
다음:
  /ax-study concept {개념명}   ← 개념 재학습
  /ax-study feynman {개념명}   ← 다시 도전
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Error Reference

| Condition | Response |
|---|---|
| `study-notes.md` missing or active-document empty | "No active study. Run `/ax-study <pdf-path-or-url>` to start." |
| notebooklm MCP unavailable | "notebooklm MCP server가 연결되어 있지 않습니다. `~/.claude/settings.json`의 `notebooklm-mcp` 설정을 확인하세요." |
| context7 unavailable (concept mode) | Skip background step silently, continue with NLM result only |
| source_add fails | Report error verbatim, suggest checking file path or URL |
| notebook not found, create fails | Report error, suggest running `nlm login` to re-authenticate |
| studio_status timeout after 5 polls | "오디오 생성이 오래 걸리고 있습니다. 잠시 후 NLM에서 직접 확인하세요." |
