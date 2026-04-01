# AX — Personal Agent Control Plane

AX는 Claude Code + gstack + OMC + Codex를 통합하는 개인용 plugin입니다.
세션 간 메모리 유지, skill 라우팅, research 기록 자동 수집을 처리합니다.

## What it does

| 기능 | 설명 |
|------|------|
| **세션 메모리** | SessionEnd hook → MEMORY.md 자동 갱신 |
| **Skill 라우팅** | `/ax <task>` → 최적 skill 추천 |
| **Research 수집** | 실험 로그, 논문 계획 등 project 파일 자동 인제스트 |

## Install

### Plugin Marketplace (권장)

```
/plugin marketplace add https://github.com/mqjinwon/ax-claude
/plugin install ax-claude
/ax-setup
```

`/ax-setup`이 자동으로 처리:
- python3 + pyyaml 설치 (없는 경우)
- 모든 `.sh` 스크립트 실행 권한 부여
- PATH 설정 안내

SessionEnd hook과 `/ax` skill은 **plugin system이 자동 등록**.

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

### 인사이트 기록

```
/ax learn MEMORY.md section 간 deduplication은 entry ID로 처리
```

`decisions` section에 타임스탬프와 함께 기록.

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
~/.ax/
├── bin/
│   └── ax                  # CLI (init, ingest, status, upgrade)
├── adapters/
│   ├── ax-ingest.sh        # SessionEnd hook orchestrator
│   ├── ingest-gstack.sh    # gstack eureka + skill usage 수집
│   ├── ingest-omc.sh       # OMC mission + session 수집
│   └── ingest-research.sh  # Research output 파일 수집
├── lib/
│   └── ax-utils.sh         # MEMORY.md section manipulation helpers
├── routing/
│   └── skill-routing.yaml  # /ax 라우팅 규칙 (7 categories)
├── templates/
│   └── MEMORY.template.md  # ax init 시 사용하는 MEMORY.md 템플릿
├── SKILL.md                # /ax skill definition
├── setup                   # Install / reinstall script
├── uninstall               # Uninstall script
├── VERSION                 # Version string
└── README.md               # This file
```

## Requirements

- bash 4+
- jq (`sudo apt install jq` / `brew install jq`)
- Claude Code CLI
- python3 + pyyaml — `/ax` 라우팅용 (`setup`이 자동 설치, 없으면 fallback 동작)

## How MEMORY.md works

```
SessionEnd hook fires
  └── ax-ingest.sh (reads cwd from stdin JSON)
        ├── ingest-gstack.sh  → decisions + session-history sections
        ├── ingest-omc.sh     → active-context + session-history sections
        └── ingest-research.sh → research-notes section
```

각 어댑터는 entry ID 기반 중복 제거 (`<!-- entry:ID -->` 마커)를 사용합니다.
