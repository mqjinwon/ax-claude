# AX — Personal Agent Control Plane

AX는 Claude Code + gstack + OMC + Codex를 통합하는 개인용 plugin입니다.
세션 간 메모리 유지, skill 라우팅, research 기록 자동 수집을 처리합니다.

## What it does

| 기능 | 설명 |
|------|------|
| **세션 메모리** | SessionEnd hook → MEMORY.md 자동 갱신 |
| **Skill 라우팅** | `/ax <task>` → 최적 skill 추천 |
| **Guide Mode** | `/ax learn` → 전체 skill 계층 + 라우팅 카테고리 가이드 출력 |
| **인사이트 기록** | `/ax learn <내용>` → decisions.md에 타임스탬프와 함께 기록 |
| **메모리 보호** | PreToolUse hook → `.ax/memory/` 직접 Write/Edit 차단 (ax-ingest.sh 전용 관리) |
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
- PATH 자동 추가 (`~/.bashrc` 또는 `~/.zshrc`)
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

`<project>/.ax/memory/MEMORY.md` 생성 + Claude 네이티브 메모리 경로에 symlink.

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

### 수동 인제스트

```bash
ax ingest    # MEMORY.md 지금 바로 갱신
ax status    # 현재 프로젝트 ax 상태 확인
```

## Upgrade

Plugin 설치 시:
```
/plugin install ax-claude
```

수동 설치 시:
```bash
ax upgrade
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
│   └── ax                  # CLI (init, ingest, status, upgrade)
├── adapters/
│   ├── ax-ingest.sh        # SessionEnd hook orchestrator
│   ├── ingest-gstack.sh    # gstack eureka + skill usage 수집
│   ├── ingest-omc.sh       # OMC mission + session 수집
│   └── ingest-research.sh  # Research output 파일 수집
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
  ├── decisions.md         ← 결정 이력 (gstack eureka + /ax learn)
  ├── research-notes.md    ← research output 파일 요약
  ├── experiment-log.md    ← eval_results.json 결과 기록
  └── study-notes.md       ← 문서 학습 진행상황 (/ax-study)
```

ingest 흐름:

```
SessionEnd hook fires
  └── ax-ingest.sh (reads cwd from stdin JSON)
        ├── topic 파일 bootstrap (decisions / research-notes / experiment-log)
        ├── ingest-gstack.sh  → decisions.md + session-history (MEMORY.md)
        ├── ingest-omc.sh     → active-context + session-history (MEMORY.md)
        └── ingest-research.sh → research-notes.md + experiment-log.md
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
