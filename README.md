# AX — Personal Agent Control Plane

AX는 Claude Code + OMC + Codex를 통합하는 개인용 plugin입니다.
세션 간 메모리 유지, skill 라우팅, research 기록 자동 수집을 처리합니다.

**현재 버전**: 1.18.0 | [CHANGELOG](CHANGELOG.md)

## What it does

| 기능 | 설명 |
|------|------|
| **세션 메모리** | SessionEnd hook → MEMORY.md 자동 갱신 |
| **Skill 라우팅** | `/ax <task>` → 최적 skill 추천 (4-tier: override → keyword → TF-IDF → LLM) |
| **Guide Mode** | `/ax learn` → 전체 skill 계층 + 라우팅 카테고리 가이드 출력 |
| **인사이트 기록** | `/ax learn <내용>` → decisions.md에 타임스탬프와 함께 기록 |
| **자동 라우팅 힌트** | UserPromptSubmit hook → 매 입력마다 관련 skill 자동 제안 |
| **메모리 보호** | PreToolUse hook → `.ax/memory/` 직접 Write/Edit 차단 |
| **Rate Limit Auto-Resume** | usage ≥80% 경고 → ≥90% 도구 중단 + 작업 저장 → 100% 시 자동 재개 |
| **Split Memory** | MEMORY.md(인덱스) + topic 파일(decisions / research-notes / experiment-log / study-notes) |
| **Research 수집** | 9가지 research output 파일 자동 감지 → research-notes.md 기록 |
| **실험 결과 수집** | `eval_results.json` 자동 감지 → experiment-log.md 기록 |
| **문서 학습** | `/ax-study` — NotebookLM + Active Recall Quiz + Feynman 검증 + 진행 추적 |

## Install

### Plugin Marketplace (권장)

```
/plugin marketplace add https://github.com/mqjinwon/ax-claude
/plugin install ax-claude
/ax-setup
```

`/ax-setup` 한 번으로 자동 완료:
- pyyaml 설치 (없는 경우)
- 스크립트 실행 권한 설정
- 활성 plugin 루트를 우선 사용해 stale cache 경로를 피함
- 현재 프로젝트 `ax init` 자동 실행

SessionEnd hook과 `/ax` skill은 **plugin system이 자동 등록**.

> **이미 `/plugin marketplace add`를 실행했다면**: 마켓플레이스를 제거 후 재추가해야 합니다.
> ```
> /plugin marketplace remove ax-claude
> /plugin marketplace add https://github.com/mqjinwon/ax-claude
> /plugin install ax-claude
> ```

### 수동 설치 (legacy)

```bash
git clone https://github.com/mqjinwon/ax-claude ~/.ax
~/.ax/setup
```

PATH에 추가 (`.bashrc` 또는 `.zshrc`):

```bash
export PATH="$HOME/.ax/bin:$PATH"
```

## Usage

### 프로젝트 초기화

```bash
cd ~/my-project
ax init
```

`<project>/.ax/memory/MEMORY.md` 생성 (Layer 2). Claude auto-memory(Layer 1)와 분리 운영됩니다.

> **v1.10.x 이하에서 업그레이드 시**: Layer 1 symlink를 수동으로 제거하세요:
> ```bash
> rm ~/.claude/projects/<project-hash>/memory/MEMORY.md
> mv ~/.claude/projects/<project-hash>/memory/MEMORY.md.bak \
>    ~/.claude/projects/<project-hash>/memory/MEMORY.md
> ```

### 세션 시작 시 컨텍스트 복원

```
/ax
```

Active context, open problems, recent sessions, recent decisions를 보여줍니다.

### Skill 라우팅 (4-tier)

```
/ax 버그 찾아야 해
/ax 논문 실험 설계
/ax 코드 리뷰
```

task 설명 → 최적 skill 추천. 라우팅은 4단계로 처리됩니다:

1. **Project override**: `.ax/memory/MEMORY.md`의 routing-overrides 섹션 확인
2. **Keyword 매칭**: `skill-routing.yaml` trigger 키워드와 정확 매칭
3. **TF-IDF 유사도**: `examples:` 필드 예문과 의미적 유사도 비교 (v1.17+)
4. **LLM fallback**: 위 3단계 미매칭 시 Claude 판단

Routing Mode는 카테고리에 따라 관련 topic 파일(decisions.md / research-notes.md / experiment-log.md)을 자동으로 읽어 컨텍스트도 함께 제공합니다.

### 자동 라우팅 힌트 (v1.16+)

매 입력마다 UserPromptSubmit hook이 실행되어 관련 skill을 자동 제안합니다.
별도 `/ax` 호출 없이도 task에 맞는 skill을 힌트로 표시합니다.

### Skill 가이드 보기

```
/ax learn
```

전체 skill 계층 구조와 라우팅 카테고리를 출력합니다 (Guide Mode).

### 인사이트 기록

```
/ax learn MEMORY.md section 간 deduplication은 entry ID로 처리
```

`decisions.md`에 타임스탬프와 함께 기록됩니다.

### Project-level Routing Overrides

특정 키워드에 대해 프로젝트별 skill 라우팅을 override할 수 있습니다:

```
/ax learn route: <keyword> → <skill>
```

예시:

```
/ax learn route: 하네스 → planning
```

이후 `/ax 하네스 엔지니어링 개선` 실행 시 `planning`으로 라우팅됩니다.
동일한 override를 두 번 실행하면 중복 추가를 건너뜁니다.

### 문서 학습 (ax-study)

NotebookLM과 연동해 프로젝트별 학습 공간을 만듭니다.

```
/ax-study paper.pdf              # PDF 등록 → NLM 노트북 생성 + 학습 로드맵
/ax-study https://arxiv.org/...  # URL 등록
/ax-study                        # 진행상황 확인 + 다음 단계 제안
/ax-study concept PPO            # 개념 심화 학습 (NLM 쿼리 + context7 보충)
/ax-study explore sim2real       # 후속 연구 skill 추천 (arxiv / semantic-scholar)
/ax-study audio                  # 오디오 요약 생성 (mp3 다운로드)
/ax-study quiz [N]               # Active Recall 퀴즈 (기본 5문제, N 지정 가능)
/ax-study feynman <개념>         # Feynman 검증 — 멀티턴 소크라테스 대화
```

> **v1.19+**: `feynman`과 `quiz` 명령 실행 시 로컬 브라우저 UI 자동 오픈.
> Light/Dark 모드 지원. 답변을 터미널 대신 브라우저에서 입력.

```
```

**자연어 입력도 지원** (v1.18+):

```
/ax-study transformer 이해 안가  → feynman 모드 자동 진입
/ax-study 퀴즈 내줘              → quiz 모드 자동 진입
/ax-study PPO 알려줘             → concept 모드 자동 진입
```

**Quiz 모드**: Active Recall Q&A 세션. NLM 연결 시 notebook 기반 문제 생성, 없으면 Claude fallback. 결과는 `mastery` 섹션에 자동 기록 (`weak` / `learning` / `mastered`).

**Feynman 모드**: 최대 5라운드 소크라테스 대화. 개념을 직접 설명하면 Claude가 갭을 탐지하고 심화 질문. 갭 없으면 조기 완료. 결과는 `feynman-passed` 태그로 기록.

학습 내용은 프로젝트별 `study-notes.md`에 자동 저장됩니다:
- 진행 중인 문서, 섹션별 완료 여부
- 개념별 요약 노트 (entry ID 기반 중복 없음)
- 미해결 질문 추적
- mastery 레벨 및 다음 복습 날짜 (v1.18+)

### Memory Compaction (자동 압축)

세션 종료 시 ingest가 끝나면 topic 파일들의 크기를 자동으로 관리합니다.
항목 수가 `AX_COMPACT_HARD_CAP`을 초과하면, 오래된 항목들을 하나의 compact notice로 대체합니다.

**기본값:**
| 환경 변수 | 기본값 | 설명 |
|-----------|--------|------|
| `AX_COMPACT_HARD_CAP` | `20` | 이 수를 초과하면 압축 실행 |
| `AX_COMPACT_KEEP_RECENT` | `15` | 압축 후 원본으로 보존할 최신 항목 수 |

**env var 오버라이드 예시:**
```bash
export AX_COMPACT_HARD_CAP=50
export AX_COMPACT_KEEP_RECENT=40
```

### Rate Limit Auto-Resume (v1.14+)

Claude Code 5시간 usage quota를 자동으로 처리합니다.

| Usage % | 동작 |
|---------|------|
| ≥ 80%   | Claude에게 경고 표시 — 작업 저장 권장 |
| ≥ 90%   | Write/Edit 외 모든 도구 차단; Claude가 작업 파일 저장 |
| = 100%  | 전체 도구 차단; 백그라운드 watcher 실행 |

quota가 리셋되면 `claude --continue`가 자동으로 호출됩니다.

**임계값 설정** (`.ax/config.yaml`, `ax init` 시 자동 생성):
```yaml
warn_at: 80
pause_at: 90
block_at: 100
auto_resume: true
```

## Upgrade

```
/plugin install ax-claude
```

## Uninstall

Plugin 설치 시:
```
/plugin uninstall ax-claude
```

수동 설치 시:
```bash
~/.ax/uninstall
```

**보존 대상**: 모든 프로젝트 `.ax/` 데이터 (삭제되지 않음)

## Directory Structure

```
~/.ax/  (or plugin cache when installed via marketplace)
├── .claude-plugin/
│   ├── marketplace.json    # Plugin marketplace manifest
│   └── plugin.json         # Plugin metadata (skills, hooks 경로)
├── bin/
│   ├── ax                  # CLI (init, ingest, status, upgrade)
│   ├── ax-route.py         # /ax keyword + TF-IDF router
│   ├── ax-learn.py         # /ax learn 인사이트 파싱 + routing override
│   ├── ax-guide.py         # /ax learn (no args) skill 계층 출력
│   ├── ax-compact.py       # Memory compaction engine
│   └── ax-usage.sh         # OAuth usage API library
├── adapters/
│   ├── ax-ingest.sh          # SessionEnd hook orchestrator
│   ├── ingest-omc.sh         # OMC mission + session 수집
│   ├── ingest-research.sh    # Research output 파일 수집
│   ├── ingest-routing.sh     # ax-learn.py 호출 자동화
│   └── ax-memory-compact.sh  # Rolling Summary + Hard Cap 자동 압축
├── hooks/
│   ├── hooks.json          # SessionEnd + PreToolUse + UserPromptSubmit hook 정의
│   ├── ax-write-guard.sh   # PreToolUse: .ax/memory/ 직접 write 차단 + rate limit
│   └── ax-auto-route.sh    # UserPromptSubmit: 자동 skill 라우팅 힌트
├── lib/
│   └── ax-utils.sh         # MEMORY.md section manipulation helpers
├── routing/
│   └── skill-routing.yaml  # /ax 라우팅 규칙 (14 categories)
├── skills/
│   ├── ax/SKILL.md         # /ax skill (resume, routing, learn)
│   ├── ax-setup/SKILL.md   # /ax-setup skill (post-install setup)
│   └── ax-study/SKILL.md   # /ax-study skill (문서 학습 + quiz + feynman)
├── templates/
│   ├── MEMORY.template.md
│   ├── DECISIONS.template.md
│   ├── RESEARCH_NOTES.template.md
│   ├── EXPERIMENT_LOG.template.md
│   └── STUDY_NOTES.template.md
├── setup                   # Manual install script (legacy)
├── uninstall               # Manual uninstall script (legacy)
├── VERSION                 # Version string
└── README.md
```

## Troubleshooting

### `/plugin install ax-claude` — "Plugin not found in any marketplace"

```
/plugin marketplace remove ax-claude
/plugin marketplace add https://github.com/mqjinwon/ax-claude
/plugin install ax-claude
```

### `/ax` skill이 없다고 나옴

plugin 설치 후 Claude Code를 재시작하면 skills가 자동 로드됩니다.

## Requirements

- bash 4+
- jq (`sudo apt install jq` / `brew install jq`)
- Claude Code CLI
- python3 + pyyaml — `/ax` 라우팅용 (`setup`이 자동 설치)

## How Memory works

v1.4부터 메모리는 여러 파일로 분리됩니다 (Split Memory).

```
<project>/.ax/memory/
  ├── MEMORY.md            ← 인덱스: active-context, session-history, open-problems
  ├── decisions.md         ← 결정 이력 (/ax learn)
  ├── research-notes.md    ← research output 파일 요약
  ├── experiment-log.md    ← eval_results.json 결과 기록
  └── study-notes.md       ← 문서 학습 진행상황 (/ax-study)
```

ingest 흐름:

```
SessionEnd hook fires
  └── ax-ingest.sh
        ├── topic 파일 bootstrap
        ├── ingest-omc.sh       → active-context + session-history
        ├── ingest-research.sh  → research-notes.md + experiment-log.md
        ├── ingest-routing.sh   → ax-learn.py (routing override 동기화)
        └── ax-memory-compact.sh → 자동 압축 (cap 초과 시)
```

### Research output 자동 감지

| 파일 | 출처 skill |
|------|-----------|
| `PAPER_PLAN.md` | `/paper-plan` |
| `PAPER_IMPROVEMENT_LOG.md` | `/auto-review-loop` |
| `EXPERIMENT_LOG.md` | `/run-experiment` |
| `CLAIMS_FROM_RESULTS.md` | `/result-to-claim` |
| `AUTO_REVIEW.md` | `/auto-review-loop` |
| `NARRATIVE_REPORT.md` | `/research-refine` |
| `refine-logs/FINAL_PROPOSAL.md` | `/research-refine` |
| `IDEA_REPORT.md` | `/idea-discovery` |
| `LITERATURE_REPORT.md` | `/research-lit` |
| `eval_results.json` | `/run-experiment` → `experiment-log.md` |
