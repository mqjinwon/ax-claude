# AX — Personal Agent Control Plane

AX는 Claude Code + OMC + Codex를 통합하는 개인용 plugin입니다.
세션 간 메모리 유지, skill 라우팅, research 기록 자동 수집을 처리합니다.

## What it does

| 기능 | 설명 |
|------|------|
| **세션 메모리** | SessionEnd hook → MEMORY.md 자동 갱신 |
| **Skill 라우팅** | `/ax <task>` → 최적 skill 추천 |
| **Guide Mode** | `/ax learn` → 전체 skill 계층 + 라우팅 카테고리 가이드 출력 |
| **인사이트 기록** | `/ax learn <내용>` → decisions.md에 타임스탬프와 함께 기록 |
| **메모리 보호** | PreToolUse hook → `.ax/memory/` 직접 Write/Edit 차단 (ax-ingest.sh 전용 관리) |
| **Rate Limit Auto-Resume** | usage ≥80% 경고 → ≥90% 도구 중단 + 작업 저장 → 100% 시 자동 재개 (`claude --continue`) |
| **Split Memory** | MEMORY.md(인덱스) + topic 파일(decisions / research-notes / experiment-log) |
| **Research 수집** | 9가지 research output 파일 자동 감지 → research-notes.md 기록 |
| **실험 결과 수집** | `eval_results.json` 자동 감지 → experiment-log.md 기록 |
| **문서 학습** | `/ax-study` — NotebookLM + 진행 추적 + 개념 축적 |

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

### Skill 라우팅

```
/ax 버그 찾아야 해
/ax 논문 실험 설계
/ax 코드 리뷰
```

task 설명 → 최적 skill 추천 (`→ /investigate`, `→ /plan-eng-review` 등).

Routing Mode는 카테고리에 따라 관련 topic 파일(decisions.md / research-notes.md / experiment-log.md)을 자동으로 읽어 컨텍스트도 함께 제공합니다.

### Skill 가이드 보기

```
/ax learn
```

전체 skill 계층 구조와 라우팅 카테고리를 출력합니다 (Guide Mode).

### 인사이트 기록

```
/ax learn MEMORY.md section 간 deduplication은 entry ID로 처리
```

`decisions.md`에 타임스탬프와 함께 기록 (v1.4+: decisions.md 별도 파일).

### Project-level Routing Overrides

특정 키워드에 대해 프로젝트별 skill 라우팅을 override할 수 있습니다:

```
/ax learn route: <keyword> → <skill>
```

예시:

```
/ax learn route: 하네스 → planning
```

이후 `/ax 하네스 엔지니어링 개선` 실행 시 global keyword 매칭 대신 `planning`으로 라우팅됩니다.

Override는 `.ax/memory/MEMORY.md`의 `## Routing Overrides` 섹션에 저장됩니다. `skill-routing.yaml` keyword 매칭보다 우선 적용됩니다.

동일한 override를 두 번 실행하면 "already exists" 메시지와 함께 중복 추가를 건너뜁니다.

### 문서 학습 (ax-study)

NotebookLM과 연동해 프로젝트별 학습 공간을 만듭니다.

```
/ax-study paper.pdf          # PDF 등록 → NLM 노트북 생성 + 학습 로드맵
/ax-study                    # 진행상황 확인 + 다음 단계 제안
/ax-study concept PPO        # 개념 심화 학습 (NLM 쿼리 + context7 보충)
/ax-study explore sim2real   # 후속 연구 스킬 추천 (arxiv / semantic-scholar)
/ax-study audio              # 오디오 요약 생성 (mp3 다운로드)
```

학습 내용은 프로젝트별 `study-notes.md`에 자동 저장됩니다:
- 진행 중인 문서, 섹션별 완료 여부
- 개념별 요약 노트 (entry ID 기반 중복 없음)
- 미해결 질문 추적

> **quiz, report, explain** 등 NLM 직접 기능은 `/notebooklm-study`를 사용하세요.

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
# decisions.md를 최대 50개, 최근 40개 보존으로 설정
export AX_COMPACT_HARD_CAP=50
export AX_COMPACT_KEEP_RECENT=40
```

**compact notice 형식** (압축된 항목들이 이 형식으로 대체됩니다):
```markdown
<!-- entry:compact-202604021200 -->
**2026-04-02** [compacted 8 entries, 2026-01-01..2026-03-15]:
- [2026-01-01] Filesystem-based memory beats vector DB
- [2026-03-31] P1/P3/P4 구현 완료, v1.9.0
...
```

압축 대상 파일: `decisions.md`, `research-notes.md`, `experiment-log.md`, `study-notes.md`

### Rate Limit Auto-Resume

Claude Code 5시간 usage quota를 자동으로 처리합니다.

| Usage % | 동작 |
|---------|------|
| ≥ 80%   | Claude에게 경고 표시 — 작업 저장 권장 |
| ≥ 90%   | Write/Edit 외 모든 도구 차단; Claude가 작업 파일 저장 |
| = 100%  | 전체 도구 차단; 백그라운드 watcher 실행 |

quota가 리셋되면 `claude --continue`가 자동으로 호출됩니다.

**작업 사전 등록** (장시간 자율 실행에 권장):
```bash
ax queue "implement the new auth system"
```

**임계값 설정** (`.ax/config.yaml`, `ax init` 시 자동 생성):
```yaml
warn_at: 80      # % — 경고만
pause_at: 90     # % — 작업 저장 + 차단
block_at: 100    # % — 전체 차단
auto_resume: true
```

Watcher 로그: `.ax/resume-watcher.log`


## Upgrade

Plugin 설치 시:
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
│   ├── ax-route.py         # /ax keyword router
│   └── ax-compact.py       # Memory compaction engine (Rolling Summary + Hard Cap)
├── adapters/
│   ├── ax-ingest.sh          # SessionEnd hook orchestrator
│   ├── ingest-omc.sh         # OMC mission + session 수집
│   ├── ingest-research.sh    # Research output 파일 수집
│   └── ax-memory-compact.sh  # Rolling Summary + Hard Cap 자동 압축
├── hooks/
│   ├── hooks.json          # SessionEnd + PreToolUse hook 정의 (plugin system 등록용)
│   └── ax-write-guard.sh   # PreToolUse: .ax/memory/ 직접 write 차단
├── lib/
│   └── ax-utils.sh         # MEMORY.md section manipulation helpers
├── routing/
│   └── skill-routing.yaml  # /ax 라우팅 규칙 (7 categories)
├── skills/
│   ├── ax/
│   │   └── SKILL.md        # /ax skill (resume, routing, learn)
│   ├── ax-setup/
│   │   └── SKILL.md        # /ax-setup skill (post-install setup)
│   └── ax-study/
│       └── SKILL.md        # /ax-study skill (문서 학습)
├── templates/
│   ├── MEMORY.template.md          # ax init 시 사용하는 MEMORY.md 템플릿
│   ├── DECISIONS.template.md       # decisions.md 초기화 템플릿
│   ├── RESEARCH_NOTES.template.md  # research-notes.md 초기화 템플릿
│   ├── EXPERIMENT_LOG.template.md  # experiment-log.md 초기화 템플릿
│   └── STUDY_NOTES.template.md     # study-notes.md 초기화 템플릿
├── SKILL.md                # /ax skill source (legacy / git clone용)
├── setup                   # Manual install script (legacy)
├── uninstall               # Manual uninstall script (legacy)
├── VERSION                 # Version string
└── README.md               # This file
```

## Troubleshooting

### `/plugin install ax-claude` — "Plugin not found in any marketplace"

`/plugin marketplace add`가 성공했더라도 등록에 실패했을 수 있습니다. 다음 순서로 재시도:

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
- python3 + pyyaml — `/ax` 라우팅용 (`setup`이 자동 설치, 없으면 fallback 동작)

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
  └── ax-ingest.sh (reads cwd from stdin JSON)
        ├── topic 파일 bootstrap (decisions / research-notes / experiment-log)
        ├── ingest-omc.sh       → active-context + session-history (MEMORY.md)
        ├── ingest-research.sh  → research-notes.md + experiment-log.md
        └── ax-memory-compact.sh → topic 파일 자동 압축 (cap 초과 시)
```

각 어댑터는 entry ID 기반 중복 제거 (`<!-- entry:ID -->` 마커)를 사용합니다.

### Research output 자동 감지

프로젝트 루트에 아래 파일이 있으면 자동으로 `research-notes.md`에 기록됩니다:

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
