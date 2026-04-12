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

## Quiz Mode

**Trigger**: `/ax-study quiz [N]` 또는 자연어 퀴즈 의도 (Mode Detection 참고)

N 미지정 시 기본 5문제. `quiz 10`처럼 숫자 지정 가능.

### Step 1: 컨텍스트 로드

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
echo "=== CONCEPT NOTES ==="
ax_get_section "$STUDY_NOTES" "concept-notes"
```

active-document가 비어 있으면: "No active study. Run `/ax-study <pdf-path-or-url>` to start." 출력 후 Hint Footer(초기) 표시하고 종료.

> **기존 프로젝트 호환:** mastery/next-review 섹션이 study-notes.md에 없으면 `ax_replace_section`이 새 섹션으로 삽입한다 (ax-utils.sh 표준 동작).

### Step 2: 문제 생성 (하이브리드)

**N** = 사용자가 지정한 숫자 또는 기본값 5.

**NLM 경로 (연결 있을 때):**

notebook_id를 active-document에서 읽어 `notebook_query` MCP 호출:

```
query: "Generate {N} Q&A pairs covering the key concepts of this document.
Format each pair exactly as:
Q: [question in Korean or English matching the document language]
A: [concise answer, 1-3 sentences]

Focus on concepts that require deep understanding, not simple facts."
```

**Claude fallback (NLM 없거나 실패 시):**

`concept-notes` 섹션의 각 `### {Concept Name}` 항목에서 Q&A 생성:
- Q: Definition/Key insight 기반 질문
- A: Definition + Key insight 결합 답변

최대 N개 생성. concept-notes 항목이 N보다 적으면 가능한 만큼만.

### Step 3: 퀴즈 세션 진행

문제를 한 번에 하나씩 제시. 사용자 답변 후 다음 문제로 이동.

**출력 형식 (문제별):**

```
**Q{번호}/{총}: {질문}**

> (답변을 입력하세요)
```

**사용자 답변 후 평가:**

```
✅ 정답 — {한 줄 피드백}
```
또는
```
⚠️ 부분 정답 — 빠진 점: {설명}
   정답: {핵심 답변}
```
또는
```
❌ 틀림 — 정답: {핵심 답변}
   핵심 포인트: {1-2줄 설명}
```

세션 중 `그만` / `skip` / `stop` 입력 시 즉시 종료 후 Step 4로.

### Step 4: study-notes.md 업데이트

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
REVIEW_DATE=$(date -d "+3 days" +%Y-%m-%d 2>/dev/null || date -v+3d +%Y-%m-%d 2>/dev/null || echo "unknown")

# mastery 섹션 업데이트 (기존 항목 유지, 신규/변경만 반영)
MASTERY_FILE=$(mktemp)
ax_get_section "$STUDY_NOTES" "mastery" \
  | grep -v '^_No mastery data yet' > "$MASTERY_FILE" || true

# quiz 결과에 따라 아래 형식으로 추가/갱신 (실제 개념명으로 교체):
# ✅ 정답: printf '- %s: mastered\n' "<CONCEPT_NAME>" >> "$MASTERY_FILE"
# ⚠️ 부분 정답: printf '- %s: learning\n' "<CONCEPT_NAME>" >> "$MASTERY_FILE"
# ❌ 틀림: printf '- %s: weak\n' "<CONCEPT_NAME>" >> "$MASTERY_FILE"

ax_replace_section "$STUDY_NOTES" "mastery" "$MASTERY_FILE"
rm -f "$MASTERY_FILE"

# next-review 섹션 업데이트 (weak 개념이 있을 때만)
# WEAK_CONCEPTS = 틀린 개념들 쉼표 구분 목록
# if [ -n "$WEAK_CONCEPTS" ]; then
#   REVIEW_FILE=$(mktemp)
#   ax_get_section "$STUDY_NOTES" "next-review" \
#     | grep -v '^_No review scheduled' > "$REVIEW_FILE" || true
#   printf '- %s: %s\n' "$REVIEW_DATE" "$WEAK_CONCEPTS" >> "$REVIEW_FILE"
#   ax_replace_section "$STUDY_NOTES" "next-review" "$REVIEW_FILE"
#   rm -f "$REVIEW_FILE"
# fi
```

### Output format

```
=== AX Study: Quiz 완료 ===

결과: {정답}/{총} 정답
정답: ✅ {개념명} ...
약점: ❌ {개념명} ...

study-notes.md mastery 업데이트 완료.
```

[Hint Footer: Quiz 완료 후 형식 사용 — 약점 있으면 "Quiz 완료 후", 없으면 "Quiz 전체 정답" 형식]

---

## Feynman Mode

**Trigger**: `/ax-study feynman <개념명>` 또는 자연어 Feynman 의도 (Mode Detection 참고)

개념명이 없으면 먼저 묻는다: "어떤 개념이 어려우신가요?"

최대 5라운드. 갭이 없으면 조기 완료.

### Step 0: 웹 서버 기동

개념명이 없으면 먼저 묻는다: "어떤 개념이 어려우신가요?" (이후 CONCEPT에 대입)

```bash
CONCEPT="<사용자가 입력한 개념명>"  # Claude: 실제 개념명으로 교체
AX_PID=$$
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_TOTAL=5

rm -f "$AX_PIPE" && mkfifo "$AX_PIPE"

# 초기 q-file (placeholder; Step 2에서 실제 Q1으로 덮어씀)
printf '{"mode":"feynman","concept":"%s","round":0,"total":%d,"text":"","status":"starting","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_TOTAL" > "$AX_Q_FILE"

python3 "$PLUGIN_ROOT/bin/ax-feynman-server.py" \
  --mode feynman \
  --concept "$CONCEPT" \
  --total "$AX_TOTAL" \
  --port 0 \
  --q-file "$AX_Q_FILE" \
  --pipe "$AX_PIPE" \
  --port-file "$AX_PORT_FILE" &
AX_SERVER_PID=$!

sleep 0.5
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")

# 서버 기동 실패 감지
if ! kill -0 "$AX_SERVER_PID" 2>/dev/null && [ ! -f "$AX_PORT_FILE" ]; then
  rm -f "$AX_PIPE" "$AX_Q_FILE"
  echo "웹 서버 실행 실패. pip install flask 후 재시도하세요."
  # return (Claude는 이 지점에서 Feynman Mode를 중단한다)
fi

xdg-open "http://localhost:$AX_PORT" 2>/dev/null || \
  open "http://localhost:$AX_PORT" 2>/dev/null || true
echo "🌐 Feynman UI: http://localhost:$AX_PORT"
```

CONCEPT 변수는 사용자가 입력한 개념명으로, Step 1 이전에 이미 결정되어 있어야 한다.
서버 기동 실패(python3 없거나 flask 미설치) 시: "웹 서버 실행 실패. pip install flask 후 재시도하세요." 출력 후 종료.

### Step 1: 컨텍스트 로드 및 개념명 확인

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
ax_get_section "$STUDY_NOTES" "concept-notes" | head -30
```

active-document 없으면: "No active study. Run `/ax-study <pdf-path-or-url>` to start." 출력 후 Hint Footer(초기) 표시하고 종료.

### Step 2: 라운드 1 — 설명 요청

Q1 텍스트를 q-file에 기록하고 브라우저에 표시한다:

```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
CONCEPT="<사용자가 입력한 개념명>"  # Claude: 실제 개념명으로 교체

Q1_TEXT="${CONCEPT}을 초등학생에게 설명한다고 가정하고 설명해보세요."
printf '{"mode":"feynman","concept":"%s","round":1,"total":%d,"text":"%s","status":"active","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_TOTAL" "$Q1_TEXT" > "$AX_Q_FILE"
```

터미널에도 출력:
```
=== AX Study: Feynman — {개념명} ===

브라우저(http://localhost:{AX_PORT})에서 답변을 입력하고 제출하세요. [1/5]
```

pipe에서 사용자 답변 대기 (브라우저 제출 시 자동 수신):
```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
AX_LINE=$(cat "$AX_PIPE")
AX_ACTION="${AX_LINE%%:*}"   # submit | hint | giveup
AX_ANSWER="${AX_LINE#*:}"
```

- `AX_ACTION=submit` → AX_ANSWER를 사용자 설명으로 사용, Step 3으로
- `AX_ACTION=hint` → Step 3 갭 탐지 없이 Claude가 Q1 핵심 답변 출력 → 다음 라운드 진행
- `AX_ACTION=giveup` → Step 5-B로

### Step 3: 갭 탐지 (하이브리드)

**NLM 경로 (연결 있을 때):**

```
notebook_query:
  "A student explained '{concept}' as follows: '{user_explanation}'
   Based on this document, what key points are missing or incorrect?
   List each gap as a single question I can ask the student to guide them.
   If the explanation is complete and correct, respond with exactly: COMPLETE"
```

**Claude fallback (NLM 없거나 실패 시):**

`concept-notes`의 해당 개념 항목(`Definition`, `Key insight`, `Related` 필드)을 기준으로 사용자 설명과 비교하여 갭을 판단한다. 갭이 없으면 `COMPLETE`로 처리.

### Step 4: 라운드 2~5 — 소크라테스 질문 또는 완료

**갭 없음 (COMPLETE 또는 Claude 판단):**

→ Step 5-A (완료 처리)

**갭 있음:**

```
[{현재라운드}/{최대라운드}] {갭 기반 소크라테스 질문}
```

다음 질문을 q-file에 기록:
```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
AX_CURRENT_ROUND=<현재 라운드 번호>  # Claude: 현재 진행 중인 라운드 번호 (2~5)
CONCEPT="<사용자가 입력한 개념명>"  # Claude: 실제 개념명으로 교체
QN_TEXT="{갭 기반 소크라테스 질문 텍스트}"
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"%s","status":"active","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_CURRENT_ROUND" "$AX_TOTAL" "$QN_TEXT" > "$AX_Q_FILE"
```

pipe에서 답변 대기:
```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
AX_LINE=$(cat "$AX_PIPE")
AX_ACTION="${AX_LINE%%:*}"
AX_ANSWER="${AX_LINE#*:}"
```

- `AX_ACTION=submit` → 답변으로 다시 Step 3
- `AX_ACTION=hint` → 현재 갭 답변 출력 후 다음 라운드
- `AX_ACTION=giveup` → Step 5-B

### Step 5-A: 완료 처리 및 study-notes.md 업데이트

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

# mastery 업데이트: feynman-passed (실제 개념명으로 <CONCEPT_NAME> 교체)
# Claude: <CONCEPT_NAME>을 실제 개념명(CONCEPT 변수값)으로 교체하여 실행
# MASTERY_FILE=$(mktemp)
# ax_get_section "$STUDY_NOTES" "mastery" \
#   | grep -v "^- <CONCEPT_NAME>:" \
#   | grep -v '^_No mastery data yet' > "$MASTERY_FILE" || true
# printf '- %s: feynman-passed\n' "<CONCEPT_NAME>" >> "$MASTERY_FILE"
# ax_replace_section "$STUDY_NOTES" "mastery" "$MASTERY_FILE"
# rm -f "$MASTERY_FILE"

# concept-notes 해당 항목에 Feynman 날짜 기록
# 해당 개념의 concept-notes 항목을 찾아 "- **Feynman**: {DATE}" 라인을 추가한다.
# ax_get_section으로 concept-notes를 읽어 해당 entry를 수정 후 ax_replace_section으로 저장.
```

q-file status를 complete로 업데이트하고 서버를 종료한다:
```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
AX_CURRENT_ROUND=<완료된 라운드 번호>  # Claude: 마지막으로 완료된 라운드 번호
CONCEPT="<사용자가 입력한 개념명>"  # Claude: 실제 개념명으로 교체
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"완료","status":"complete","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "${AX_CURRENT_ROUND:-5}" "$AX_TOTAL" > "$AX_Q_FILE"
sleep 1
curl -s "http://localhost:$AX_PORT/shutdown" >/dev/null 2>&1 || true
rm -f "$AX_Q_FILE" "$AX_PIPE" "$AX_PORT_FILE"
```

### Step 5-B: 중단 처리 및 study-notes.md 업데이트

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

# mastery 업데이트: weak (실제 개념명으로 <CONCEPT_NAME> 교체)
# Claude: <CONCEPT_NAME>을 실제 개념명(CONCEPT 변수값)으로 교체하여 실행
# MASTERY_FILE=$(mktemp)
# ax_get_section "$STUDY_NOTES" "mastery" \
#   | grep -v "^- <CONCEPT_NAME>:" \
#   | grep -v '^_No mastery data yet' > "$MASTERY_FILE" || true
# printf '- %s: weak\n' "<CONCEPT_NAME>" >> "$MASTERY_FILE"
# ax_replace_section "$STUDY_NOTES" "mastery" "$MASTERY_FILE"
# rm -f "$MASTERY_FILE"
```

q-file status를 aborted로 업데이트하고 서버를 종료한다:
```bash
# Claude: Step 0에서 사용한 AX_PID(=$$값)를 아래에 재입력
AX_PID=<Step 0의 PID값>
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
AX_TOTAL=5
AX_CURRENT_ROUND=<완료된 라운드 번호>  # Claude: 마지막으로 완료된 라운드 번호
CONCEPT="<사용자가 입력한 개념명>"  # Claude: 실제 개념명으로 교체
# Claude: WEAK_LIST에 실제 약점 개념 목록 (쉼표 구분)을 넣는다
WEAK_LIST="약점1,약점2"
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"중단","status":"aborted","result":{"score":null,"weak":["%s"]}}' \
  "$CONCEPT" "${AX_CURRENT_ROUND:-1}" "$AX_TOTAL" "$WEAK_LIST" > "$AX_Q_FILE"
sleep 1
curl -s "http://localhost:$AX_PORT/shutdown" >/dev/null 2>&1 || true
rm -f "$AX_Q_FILE" "$AX_PIPE" "$AX_PORT_FILE"
```

### Output format — 완료

```
=== AX Study: Feynman — {개념명} ===

✅ Feynman 검증 통과! ({N}라운드 완료)

핵심 인사이트:
- {핵심 포인트 1}
- {핵심 포인트 2}

study-notes.md: {개념명} → feynman-passed
```

[Hint Footer: Feynman 완료 후 형식 사용]

### Output format — 중단

```
=== AX Study: Feynman — {개념명} (중단) ===

발견된 갭:
- {미완성 포인트 목록}

study-notes.md: {개념명} → weak
```

[Hint Footer: Feynman 중단 시 형식 사용]

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
