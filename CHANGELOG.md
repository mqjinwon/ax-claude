## [1.20.0] — 2026-04-12

### Added
- `ax_migrate_topic_file`: 템플릿 버전이 올라갈 때 기존 topic 파일에 누락 섹션을 자동 append
- `ax-template-version` 헤더: 템플릿 스키마 버전 추적, 불필요한 재실행 방지
- `tests/test-ax-migration.sh`: migration 동작 검증 테스트
- `ax-study`: 순차 학습("다음") 진행 시 Study Queue `[x]` 체크 및 Progress 자동 갱신 (설계 갭 수정)

### Changed
- `ax_ensure_topic_file`: 파일이 이미 존재할 때도 `ax_migrate_topic_file`을 호출하여 스키마 마이그레이션 실행

### Fixed
- `ax_replace_section`이 존재하지 않는 섹션에 대해 silent-fail하던 문제 (근본 원인: 섹션 마커 누락) — migration으로 예방

# Changelog

All notable changes to ax-claude are documented here.
Format: `## [version] — YYYY-MM-DD` with Added / Changed / Fixed subsections.

---

## [1.19.0] — 2026-04-12

### Added
- **Feynman + Quiz 웹 UI**: 브라우저 기반 인터랙티브 학습 UI
  - `/ax-study feynman <개념>` → 즉시 브라우저 오픈, Q/A 히스토리 표시
  - `/ax-study quiz` → 브라우저에서 문제 풀기
  - 제출 / 답 받기(Feynman) / 포기 커스텀 모달
  - Light/Dark 모드 토글 (기본: Light)
  - Named pipe를 통한 브라우저 → Claude 답변 전달
  - `bin/ax-feynman-server.py`: Flask 서버 (Feynman + Quiz 공용)
- **setup**: `pip install flask` 자동 설치 추가

---

## [1.18.0] — 2026-04-12

### Added
- **AX Study v2**: `/ax-study` 대규모 업그레이드
  - **Mode Auto-Detect**: 자연어 의도 자동 감지 ("이해 안가" → feynman, "퀴즈 내줘" → quiz)
  - **Quiz 모드**: Active Recall Q&A 세션, NLM/Claude 하이브리드 문제 생성, mastery 추적
  - **Feynman 모드**: 최대 5라운드 멀티턴 소크라테스 대화, NLM/Claude 하이브리드 갭 탐지, 중단 처리
  - **Argument Hints**: 모든 응답 하단 컨텍스트 맞춤 힌트 블록 (5가지 변형)
  - **study-notes.md 스키마 확장**: `mastery` / `next-review` 섹션 추가
  - **skill-routing.yaml**: `study` 카테고리에 `examples` 필드 추가 (TF-IDF 자동 감지용)

---

## [1.17.0] — 2026-04-09

### Added
- **AX Router v2**: 4-tier routing 아키텍처
  - Tier 1: routing-override (프로젝트별 override, MEMORY.md)
  - Tier 2: keyword 매칭 (ax-route.py, skill-routing.yaml)
  - Tier 3: examples TF-IDF 유사도 매칭 (신규)
  - Tier 4: LLM semantic fallback
  - `examples:` 필드 다수 카테고리에 추가 (debugging, planning, execution 등)
- **Usage Learning System**: `/ax learn <insight>` → decisions.md 자동 기록, routing override 지원
- **ax-learn.py**: 인사이트 파싱 + routing-override 섹션 자동 업데이트
- **ingest-routing.sh**: 세션 종료 시 ax-learn.py 호출 자동화

---

## [1.16.0] — 2026-04-07

### Added
- **AX Harness v2**: 자동 skill 라우팅 + OMC 메모리 통합
  - `ax-auto-route.sh`: UserPromptSubmit hook으로 자동 skill 추천
  - OMC `project-memory.json` → `.ax/memory/decisions.md` 자동 수집 (ingest-omc.sh)
  - `omc_covered` 필드: skill-routing.yaml에서 OMC 중복 감지 억제
- **UserPromptSubmit hook** 등록: 매 입력마다 skill 라우팅 hint 표시

---

## [1.15.0] — 2026-04-05

### Fixed
- Dead reference 제거 (gstack 잔존 참조 정리)
- Memory compaction sed escaping 버그 수정
- Legacy cleanup: 미사용 adapter 및 hook 참조 제거

---

## [1.14.0] — 2026-04-03

### Added
- **Rate Limit Auto-Resume**: Claude Code 5시간 usage quota 자동 처리
  - `ax-usage.sh`: OAuth usage API 조회 + 로컬 캐시
  - `ax-write-guard.sh`: warn(80%) / pause(90%) / block(100%) 단계별 임계값
  - `ax-resume-watcher.sh`: Stop hook 트리거 + 백그라운드 자동 재개 (`claude --continue`)
  - `.ax/config.yaml` 임계값 설정 지원

---

## [1.13.0 이전] — 초기 구축

> git 히스토리 없음. README 및 코드베이스에서 역추적.

### Core Features (v1.0–v1.13)
- **`/ax` skill**: resume / routing / learn 3가지 모드
  - Resume Mode: active-context, open-problems, session-history 요약
  - Routing Mode: keyword 매칭 → canonical skill 추천
  - Learn Mode: 인사이트 → decisions.md 기록
- **`/ax-setup` skill**: pyyaml 설치, 스크립트 권한 설정, ax init 자동 실행
- **`/ax-study` skill**: NotebookLM 연동 문서 학습 (init / resume / concept / explore / audio)
- **SessionEnd hook**: 세션 종료 시 MEMORY.md 자동 갱신 (`ax-ingest.sh`)
- **PreToolUse hook**: `.ax/memory/` 직접 Write/Edit 차단 (`ax-write-guard.sh`)
- **Split Memory** (v1.4+): MEMORY.md(인덱스) + decisions / research-notes / experiment-log / study-notes 분리
- **Memory Compaction** (v1.9+): Hard Cap 초과 시 오래된 항목 자동 압축
- **Research output 자동 수집**: 9종 파일 감지 → research-notes.md 기록
- **skill-routing.yaml**: 14개 카테고리 라우팅 규칙
- **ax-guide.py**: `/ax learn` 전체 skill 계층 출력
- **Project-level routing override**: `/ax learn route: <keyword> → <skill>`
