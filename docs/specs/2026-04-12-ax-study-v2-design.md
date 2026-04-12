# AX Study v2 — Design Spec

**Date**: 2026-04-12
**Status**: Approved for implementation
**Scope**: /ax-study 스킬 개선 — 자동 모드 감지 + Argument Hints + Quiz + Feynman 모드

---

## Goal

`/ax-study`를 수동 소비 도구에서 능동 학습 도구로 전환한다.

- 사용자가 모드 이름을 외우지 않아도 자연어로 의도를 전달하면 자동 감지
- 모든 응답 하단에 컨텍스트 맞춤 힌트 고정 → 다음 액션 항상 명확
- Active Recall(Quiz) + Feynman 검증(멀티턴)으로 수동 읽기 → 능동 검색 강제

**성공 기준**:
- `"transformer 이해 안가"` → feynman 모드 자동 감지
- `"공부한 거 테스트해줘"` → quiz 모드 자동 감지
- 모든 응답 하단에 다음 액션 힌트 표시
- Quiz: NLM 연결 없어도 Claude fallback으로 동작
- Feynman: 최대 5라운드 멀티턴, 갭 없으면 조기 완료

---

## Architecture

```
/ax-study <자연어 또는 키워드>
        ↓
[Mode Auto-Detect] — 우선순위 순
  1. URL/PDF 경로 → init
  2. 명시적 키워드 → 해당 모드
  3. 자연어 의도 분류 → quiz / feynman / concept / resume
        ↓
[Mode 실행]
  init     → NLM notebook 생성 + 로드맵 (기존 유지)
  resume   → 진행 상황 표시 (기존 + 힌트 추가)
  concept  → NLM query + context7 (기존 유지)
  explore  → 스킬 추천 (기존 유지)
  audio    → NLM studio (기존 유지)
  quiz     → Active Recall Q&A 세션 [신규]
  feynman  → 멀티턴 소크라테스 대화 [신규]
        ↓
[응답 하단 고정 힌트] — 모든 모드 공통
```

---

## Component 1: Mode Auto-Detect (개선)

### 우선순위 규칙

```
1. URL / 파일 경로
   패턴: https?://, .pdf, .md, /home/, ~/
   → init 모드

2. 명시적 키워드 (기존 유지, 그대로 동작)
   "concept <X>", "explore <X>", "audio", "quiz", "feynman <X>"

3. 자연어 의도 분류 (신규)

   퀴즈 의도:
     한: "테스트", "퀴즈", "문제 내줘", "맞혀볼게", "확인해줘", "시험"
     영: "test me", "quiz me", "check my understanding"
     → quiz 모드

   Feynman 의도:
     한: "이해가 안 가", "모르겠어", "헷갈려", "다시 설명", "쉽게", "어렵다"
     영: "don't understand", "confused", "explain to me", "hard to grasp"
     + 개념명이 함께 있으면 → feynman <개념명>
     + 개념명이 없으면 → "어떤 개념이 어려우신가요?" 질문 후 feynman

   개념 의도:
     "<명사> 뭐야", "<명사> 알려줘", "<명사> 설명해줘"
     → concept <명사>

4. (아무 패턴도 없음) → resume
```

---

## Component 2: Argument Hints 시스템 (신규)

### Layer 1 — SKILL.md description 필드

```yaml
description: |
  /ax-study <pdf|url>          문서/논문 학습 시작
  /ax-study quiz               배운 내용 퀴즈 (Active Recall)
  /ax-study feynman <개념>     이해도 검증 (멀티턴 대화)
  /ax-study concept <개념>     개념 심화 학습
  /ax-study explore <주제>     후속 자료 탐색
  /ax-study audio              오디오 요약 생성
  또는 자연어: "transformer 이해 안가" → 자동 감지
```

### Layer 2 — 응답 하단 고정 힌트 (모든 모드 공통)

모든 응답의 마지막에 현재 컨텍스트에 맞는 힌트를 출력한다.

**active-document 있을 때 (기본):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
다음 액션:
  /ax-study quiz               ← 배운 내용 테스트
  /ax-study feynman <개념>     ← 이해도 검증
  /ax-study concept <개념>     ← 개념 심화
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**active-document 없을 때:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
시작하려면:
  /ax-study <pdf 경로>         ← 로컬 PDF
  /ax-study <url>              ← 웹 문서 / 논문
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Quiz 완료 후:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
결과: {정답}/{총} 정답 | 약점: [{약점 개념 목록}]
다음:
  /ax-study feynman <약점 개념>  ← 약점 집중
  /ax-study concept <약점 개념>  ← 개념 재학습
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Feynman 완료 후:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Feynman 통과: {개념명} | 숙달 상태: mastered
다음:
  /ax-study quiz               ← 전체 퀴즈로 확인
  /ax-study explore <주제>     ← 후속 탐색
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Component 3: Quiz 모드 (신규)

### 트리거

```
명시적: /ax-study quiz [숫자]
자동감지: "테스트해줘", "퀴즈", "맞혀볼게" 등
```

숫자 미지정 시 기본 5문제. `quiz 10`처럼 지정 가능.

### 문제 생성 (하이브리드)

```
NLM 연결 확인
  ↓
연결 있음:
  notebook_query("Generate {N} Q&A pairs covering key concepts.
  Format: Q: ... / A: ...")
연결 없음 (fallback):
  study-notes.md의 concept-notes 항목에서
  Claude가 직접 Q&A 생성
```

### 세션 진행

```
문제별 흐름:
  Q: {질문} [{현재}/{총}]
  > 사용자 답변
  AI 평가:
    ✅ 정답    → 해당 개념 mastery +1
    ⚠️ 부분 정답 → 빠진 점 설명 + mastery 유지
    ❌ 틀림    → 정답 제시 + mastery: weak 태그
```

### 결과 처리

```
세션 종료 시:
  - study-notes.md mastery 섹션 업데이트
  - next-review 날짜 기록 (오늘 + 3일)
  - 약점 개념 목록 → 힌트에 표시
```

---

## Component 4: Feynman 모드 (신규)

### 트리거

```
명시적: /ax-study feynman <개념명>
자동감지: "이해가 안 가" + 개념명 → feynman <개념명>
           "이해가 안 가" (개념명 없음) → "어떤 개념이 어려우신가요?" 질문
```

### 멀티턴 흐름

```
Round 1: 설명 요청
  "'{개념명}'을 초등학생에게 설명한다고 가정하고 설명해보세요."
  > 사용자 설명

  갭 탐지 (하이브리드):
    NLM 연결 있음 → notebook_query로 정답 기준 확인
    NLM 없음     → study-notes.md concept-notes 해당 항목 + Claude 판단
  갭 탐지: 빠진 핵심 개념, 잘못된 표현

Round 2~4: 갭이 있으면 소크라테스 질문
  "좋습니다. 그런데 {갭 관련 질문}? [{라운드}/5]"
  > 사용자 답변
  → 다음 갭 질문 또는 완료 판정

Round 5 또는 갭 없음: 완료
  "✅ Feynman 검증 통과: {개념명}"
  핵심 인사이트 요약 표시
```

### 중단 처리

사용자가 `포기` / `skip` / `그만` 입력 시:
- 현재까지 발견된 갭을 weak 태그로 저장
- 힌트: `/ax-study concept <개념명>`으로 재학습 권장

### study-notes.md 업데이트

```
mastery: feynman-passed 태그 추가
concept-notes 해당 항목에 "feynman: YYYYMMDD" 기록
```

---

## Component 5: study-notes.md 스키마 확장

기존 섹션 유지, 2개 섹션 추가:

```markdown
<!-- BEGIN:mastery -->
- {개념명}: weak | learning | mastered | feynman-passed
<!-- END:mastery -->

<!-- BEGIN:next-review -->
- YYYY-MM-DD: {복습 필요 개념 목록}
<!-- END:next-review -->
```

초기값: `_No mastery data yet.` / `_No review scheduled.`

mastery 레벨 정의:
- `weak`: quiz에서 틀림 또는 feynman 중단
- `learning`: 부분 정답 또는 concept 학습 완료
- `mastered`: quiz 정답
- `feynman-passed`: feynman 5라운드 이내 완료

---

## Component 6: skill-routing.yaml 업데이트

`study` 카테고리에 `examples` 필드 추가 (TF-IDF 매칭용):

```yaml
study:
  canonical: ax-study
  aliases:
    - notebooklm-study
  trigger:
    - "공부"
    - "학습"
    - "스터디"
    - "study"
    - "읽고 정리"
    - "개념 정리"
    - "문서 공부"
    - "논문 읽기"
    - "paper reading"
    - "문서 분석"
    - "deep dive 논문"
    - "읽어야 할"
  examples:                          # ← 신규
    - "이 논문 읽고 핵심 개념 정리해줘"
    - "이 개념이 이해가 잘 안 가"
    - "공부한 내용 퀴즈로 테스트해줘"
    - "Transformer 구조를 설명해야 할 것 같아"
    - "이 문서 학습 시작할게"
```

---

## File Changes Summary

| 파일 | 변경 | 내용 |
|---|---|---|
| `skills/ax-study/SKILL.md` | 수정 | description 필드 + Mode Auto-Detect 개선 + quiz/feynman 모드 추가 + 힌트 시스템 |
| `routing/skill-routing.yaml` | 수정 | `study` 카테고리 `examples` 추가 |
| `VERSION` | 수정 | 1.18.0 |
| `.claude-plugin/plugin.json` | 수정 | 1.18.0 |
| `.claude-plugin/marketplace.json` | 수정 | 1.18.0 (2곳) |

study-notes.md 스키마 변경은 SKILL.md 내 bash 블록에서 처리 (별도 파일 없음).

---

## Non-Goals

- YouTube Transcript MCP 연동 — 이번 범위 외
- Anki MCP 연동 — 이번 범위 외
- 자동 복습 알림 (cron 기반) — 이번 범위 외
- quiz 결과의 외부 저장/내보내기 — 이번 범위 외

---

## Success Criteria

1. `"transformer 이해 안가"` 입력 → feynman 모드 자동 진입
2. `"퀴즈 내줘"` 입력 → quiz 모드 자동 진입
3. 모든 응답 하단에 컨텍스트 맞춤 힌트 표시
4. NLM 연결 없어도 quiz 동작 (Claude fallback)
5. Feynman: 갭 없으면 3라운드 이내 완료 가능
6. study-notes.md에 mastery / next-review 섹션 자동 생성
7. VERSION = 1.18.0, 3파일 동기화
