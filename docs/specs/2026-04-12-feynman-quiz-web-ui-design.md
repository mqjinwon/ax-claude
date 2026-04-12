# Feynman + Quiz Web UI — Design Spec

**Date**: 2026-04-12
**Status**: Approved for implementation
**Scope**: `/ax-study feynman` + `/ax-study quiz` 실행 시 로컬 웹 UI 자동 기동

---

## Goal

Feynman 모드와 Quiz 모드에서 사용자가 Claude Code 터미널 대신 브라우저 기반 UI로 답변할 수 있도록 한다.

- 명령 실행 즉시 브라우저 자동 오픈
- Q1/A1/Q2/A2 대화 히스토리 표시
- 제출 / 답 받기 / 포기 액션을 커스텀 모달로 처리
- Light/Dark 모드 토글 (기본: Light)
- Named pipe를 통해 브라우저 답변 → Claude stdin 주입

**성공 기준**:
- `/ax-study feynman <개념>` → 1초 이내 브라우저 오픈, 질문 표시
- `/ax-study quiz` → 브라우저에서 문제 풀기 가능
- 브라우저 제출 → Claude가 답변 수신 → 다음 질문 표시 (polling 1초)
- 서버는 세션 종료 시 자동 종료

---

## Architecture

```
/ax-study feynman <개념명>  or  /ax-study quiz [N]
        ↓
SKILL.md Step 0:
  python3 $PLUGIN_ROOT/bin/ax-feynman-server.py \
    --mode feynman --concept "..." --port 0 \
    --q-file /tmp/ax-feynman-{pid}-q.json \
    --pipe /tmp/ax-feynman-{pid}.pipe &
  open browser → http://localhost:{port}?mode=feynman
        ↓
┌─────────────────────────────────────────────┐
│  ax-feynman-server.py (Flask)               │
│  GET  /           → HTML (mode별 UI)        │
│  GET  /question   → q-file JSON (1s poll)   │
│  POST /answer     → write to named pipe     │
│  GET  /shutdown   → Flask 종료              │
└─────────────────────────────────────────────┘
        ↓ named pipe (blocking)
SKILL.md: cat $PIPE → 답변 읽기 → 갭 탐지 → q-file 업데이트
        ↓ (반복)
세션 종료: curl http://localhost:{port}/shutdown → 서버 종료
```

**공유 파일** (per session):
- `/tmp/ax-feynman-{pid}-q.json` — Claude → 서버 (질문/라운드/상태)
- `/tmp/ax-feynman-{pid}.pipe` — 서버 → Claude (named pipe, blocking read)

---

## Component 1: ax-feynman-server.py

### 역할

Flask 서버. Feynman/Quiz 두 모드를 단일 서버로 처리.

### 실행 인자

```bash
python3 ax-feynman-server.py \
  --mode feynman|quiz \
  --concept "Attention Mechanism" \   # feynman 전용
  --total 5 \                          # quiz: 총 문제 수
  --port 0 \                           # 0 = OS 자동 할당
  --q-file /tmp/ax-feynman-{pid}-q.json \
  --pipe /tmp/ax-feynman-{pid}.pipe \
  --port-file /tmp/ax-feynman-{pid}-port.txt  # 서버 기동 후 실제 포트 기록
```

서버는 바인딩된 포트를 `--port-file`에 기록한 뒤 요청을 받기 시작한다.
SKILL.md는 이 파일을 읽어 브라우저 오픈 URL을 결정한다.

### Endpoints

| Method | Path | 설명 |
|--------|------|------|
| GET | `/` | HTML UI (mode별 렌더링) |
| GET | `/question` | q-file 읽어 JSON 반환. `{"round":2,"total":5,"text":"...","status":"active"}` |
| POST | `/answer` | body `{"answer":"...","action":"submit|hint|giveup"}` → named pipe에 쓰기 |
| GET | `/shutdown` | Flask 서버 종료 |

### q-file JSON 스키마

```json
{
  "mode": "feynman",
  "concept": "Attention Mechanism",
  "round": 2,
  "total": 5,
  "text": "Query, Key, Value가 어떻게 연결되나요?",
  "status": "active | complete | aborted",
  "result": {
    "score": null,
    "weak": []
  }
}
```

### named pipe 프로토콜

서버 → Claude (한 줄):
```
submit:<answer text>
hint:
giveup:
```

---

## Component 2: UI

### 공통 구조

```
[헤더] Feynman 배지 | 개념명 | 라운드 도트 ●●○○○ | ☀️/🌙 토글
[대화 히스토리]
  Q1 버블 (보라 왼쪽 border)
  A1 버블 (파랑 오른쪽 border)
  ── ROUND 2 ──
  Q2 버블 (현재, 하이라이트)
[입력 영역] sticky bottom
  [💡 답 받기] [포기]          [0자] [제출 →]
```

### Quiz 모드 차이점

- 헤더: `[Quiz]` 배지 + `문제 3 / 5`
- 히스토리: `Q3` + 선택지 없음 (주관식)
- `답 받기` 버튼 없음 (퀴즈는 힌트 없음)
- `포기` 버튼 있음 → 세션 종료 + 미응답 개념 weak 저장
- 완료 화면: 점수 `4/5` + 약점 개념 목록

### 모달 3종 (Feynman)

| 모달 | 트리거 | 내용 |
|------|--------|------|
| 제출 | 제출 버튼 | 답변 미리보기 + 취소/제출하기 |
| 답 받기 | 💡 버튼 | "답 확인 후 다음 라운드 계속" + 취소/답 보기 |
| 포기 | 포기 버튼 | "weak 저장 + 세션 종료" + 재학습 커맨드 + 계속하기/포기하기 |

### 완료/중단 화면

```
✅ Feynman 통과: Attention Mechanism (3라운드 완료)
   또는
🏳️ 세션 중단: Attention Mechanism

다음 액션:
  /ax-study quiz               ← 전체 퀴즈로 확인
  /ax-study concept <약점>     ← 약점 재학습
```

### 테마

- 기본: Light (`data-theme="light"`)
- 헤더 우측 토글 버튼으로 전환
- CSS 변수(`--bg`, `--surface`, `--text` 등)로 관리

---

## Component 3: SKILL.md 수정

### Feynman Mode Step 0 (기동) 추가

```bash
# 서버 기동
PID=$$
Q_FILE="/tmp/ax-feynman-${PID}-q.json"
PIPE="/tmp/ax-feynman-${PID}.pipe"
mkfifo "$PIPE"

# 초기 q-file 작성
printf '{"mode":"feynman","concept":"%s","round":1,"total":5,"text":"...","status":"active"}' \
  "$CONCEPT" > "$Q_FILE"

python3 "$PLUGIN_ROOT/bin/ax-feynman-server.py" \
  --mode feynman --concept "$CONCEPT" \
  --port 0 --q-file "$Q_FILE" --pipe "$PIPE" &
SERVER_PID=$!

# 포트 확인 후 브라우저 오픈 (서버가 포트를 파일에 기록)
sleep 0.5
PORT=$(cat "/tmp/ax-feynman-${PID}-port.txt" 2>/dev/null || echo 5000)
xdg-open "http://localhost:$PORT" 2>/dev/null || \
  open "http://localhost:$PORT" 2>/dev/null || true
# Claude: 사용자에게 http://localhost:{PORT} 출력 (자동 오픈 실패 대비)
```

### 라운드 루프 패턴

```bash
# 답변 대기 (blocking)
LINE=$(cat "$PIPE")
ACTION="${LINE%%:*}"   # submit | hint | giveup
ANSWER="${LINE#*:}"

# q-file 업데이트 (Claude가 다음 질문으로 교체)
# ...

# 세션 종료 시
curl -s "http://localhost:$PORT/shutdown" >/dev/null
rm -f "$Q_FILE" "$PIPE" "/tmp/ax-feynman-${PID}-port.txt"
```

---

## Component 4: setup 수정

```bash
# Flask 설치 추가
pip install flask --quiet 2>/dev/null || true
```

---

## File Changes Summary

| 파일 | 변경 | 내용 |
|---|---|---|
| `bin/ax-feynman-server.py` | 신규 | Flask 서버 (~150줄) |
| `skills/ax-study/SKILL.md` | 수정 | Feynman Mode + Quiz Mode에 서버 기동/종료 로직 추가 |
| `setup` | 수정 | `pip install flask` |
| `VERSION` | 수정 | 1.19.0 |
| `.claude-plugin/plugin.json` | 수정 | 1.19.0 |
| `.claude-plugin/marketplace.json` | 수정 | 1.19.0 (2곳) |
| `CHANGELOG.md` | 수정 | v1.19.0 항목 추가 |
| `README.md` | 수정 | 웹 UI 기능 언급 추가 |

---

## Non-Goals

- Concept 모드 웹 UI — 이번 범위 외 (단방향 출력이라 터미널로 충분)
- 원격 접속 지원 (외부 포트 바인딩) — 로컬호스트 전용
- 답변 히스토리 영구 저장 (study-notes.md 업데이트는 SKILL.md가 처리)
- 웹 UI 없이 터미널 fallback — 미지원 (서버 실패 시 에러 출력)

---

## Success Criteria

1. `/ax-study feynman <개념>` → 브라우저 자동 오픈, Q1 표시
2. 브라우저 제출 → 1초 이내 Q2 표시
3. 포기 → 세션 종료, 브라우저에 결과 화면 표시
4. Quiz 모드에서 문제 5개 순서대로 진행 가능
5. 세션 종료 시 Flask 서버 자동 종료, 임시 파일 정리
6. VERSION = 1.19.0, 3파일 동기화
