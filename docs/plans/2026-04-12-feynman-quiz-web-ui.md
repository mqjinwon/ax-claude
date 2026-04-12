# Feynman + Quiz Web UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/ax-study feynman` 및 `/ax-study quiz` 실행 시 로컬 Flask 웹 서버를 자동 기동해 브라우저 기반 Q/A UI를 제공한다.

**Architecture:** SKILL.md가 `ax-feynman-server.py`를 백그라운드로 실행하고 named pipe를 통해 사용자 답변을 수신한다. 서버는 q-file(JSON)을 polling하여 현재 질문을 제공하고, 브라우저 제출 시 named pipe에 쓴다. 클라이언트는 1초 polling으로 round 변화를 감지해 Q/A 히스토리를 로컬 상태로 관리한다.

**Tech Stack:** Python 3 + Flask, vanilla JS, Tailwind CSS CDN, named pipe (mkfifo), bash

---

## File Map

| 파일 | 역할 |
|------|------|
| `bin/ax-feynman-server.py` | 신규: Flask 서버 (endpoints + 임베디드 HTML) |
| `skills/ax-study/SKILL.md` | 수정: Feynman Mode + Quiz Mode에 서버 기동/종료 추가 |
| `setup` | 수정: `pip install flask` 추가 |
| `VERSION` | 수정: 1.19.0 |
| `.claude-plugin/plugin.json` | 수정: 1.19.0 |
| `.claude-plugin/marketplace.json` | 수정: 1.19.0 (2곳) |
| `CHANGELOG.md` | 수정: v1.19.0 항목 추가 |
| `README.md` | 수정: 웹 UI 기능 언급 |

---

## Task 1: ax-feynman-server.py — Flask 서버

**Files:**
- Create: `bin/ax-feynman-server.py`

- [ ] **Step 1: 파일 생성**

`bin/ax-feynman-server.py`를 아래 내용으로 작성한다:

```python
#!/usr/bin/env python3
"""ax-feynman-server.py — Local web server for Feynman + Quiz modes."""

import argparse
import json
import os
import sys
import threading
from pathlib import Path

try:
    from flask import Flask, jsonify, request
except ImportError:
    print("ERROR: flask not installed. Run: pip install flask", file=sys.stderr)
    sys.exit(1)

app = Flask(__name__)
_args = None
_lock = threading.Lock()


# ── Helpers ──────────────────────────────────────────────────────────────────

def read_q():
    try:
        return json.loads(Path(_args.q_file).read_text())
    except Exception:
        return {}


def write_pipe(line: str):
    try:
        with open(_args.pipe, "w") as f:
            f.write(line + "\n")
            f.flush()
    except Exception as e:
        print(f"pipe write error: {e}", file=sys.stderr)


# ── Endpoints ────────────────────────────────────────────────────────────────

HTML = None  # set in main()


@app.route("/")
def index():
    return HTML


@app.route("/question")
def question():
    return jsonify(read_q())


@app.route("/answer", methods=["POST"])
def answer():
    data = request.get_json(force=True, silent=True) or {}
    action = data.get("action", "submit")
    ans = data.get("answer", "").strip()
    if action == "submit" and ans:
        write_pipe(f"submit:{ans}")
    elif action == "hint":
        write_pipe("hint:")
    elif action == "giveup":
        write_pipe("giveup:")
    return jsonify({"ok": True})


@app.route("/shutdown")
def shutdown():
    threading.Thread(target=lambda: os._exit(0), daemon=True).start()
    return "bye"


# ── HTML template ─────────────────────────────────────────────────────────────

def build_html(mode: str, concept: str, total: int) -> str:
    mode_label = "Feynman" if mode == "feynman" else "Quiz"
    show_hint = "true" if mode == "feynman" else "false"
    return f"""<!DOCTYPE html>
<html lang="ko" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AX Study — {mode_label}</title>
<script src="https://cdn.tailwindcss.com"></script>
<style>
  :root{{--acc:#6366f1;--acc2:#4f46e5;--blue:#3b82f6}}
  [data-theme=dark]{{color-scheme:dark}}
  [data-theme=light] body{{background:#f8f9fc;color:#1e2433}}
  [data-theme=dark]  body{{background:#0f0f13;color:#e2e8f0}}
  [data-theme=light] .surface{{background:#fff;border-color:#e2e6ef}}
  [data-theme=dark]  .surface{{background:#1a1a24;border-color:#2d2d3d}}
  [data-theme=light] .surface2{{background:#f1f3f8}}
  [data-theme=dark]  .surface2{{background:#141420}}
  [data-theme=light] .bubble-q{{background:#f5f5ff;border-left:3px solid var(--acc)}}
  [data-theme=dark]  .bubble-q{{background:#1e1e2e;border-left:3px solid var(--acc)}}
  [data-theme=light] .bubble-a{{background:#f0f6ff;border-right:3px solid var(--blue)}}
  [data-theme=dark]  .bubble-a{{background:#16213e;border-right:3px solid var(--blue)}}
  .bubble-q.current{{border-left-color:#818cf8;opacity:1}}
  .overlay{{position:fixed;inset:0;background:rgba(0,0,0,.5);backdrop-filter:blur(4px);
    display:flex;align-items:center;justify-content:center;z-index:50;
    opacity:0;pointer-events:none;transition:opacity .2s}}
  .overlay.show{{opacity:1;pointer-events:all}}
  .modal{{transform:translateY(12px) scale(.97);transition:transform .2s}}
  .overlay.show .modal{{transform:none}}
  textarea:focus{{outline:none;box-shadow:0 0 0 3px rgba(99,102,241,.2)}}
  .dot{{width:8px;height:8px;border-radius:50%;background:#cbd5e1}}
  .dot.done{{background:#22c55e}}
  .dot.cur{{background:var(--acc)}}
  [data-theme=dark] .dot{{background:#2d2d3d}}
</style>
</head>
<body class="min-h-screen flex flex-col font-sans">

<!-- Header -->
<div id="hdr" class="surface border-b px-6 py-3 flex items-center justify-between sticky top-0 z-10 shadow-sm">
  <div class="flex items-center gap-3">
    <span class="text-xs font-bold uppercase tracking-widest text-white px-2 py-1 rounded" style="background:var(--acc)">{mode_label}</span>
    <span id="hdr-title" class="font-semibold text-sm">{concept or "Quiz"}</span>
  </div>
  <div class="flex items-center gap-4">
    <div class="flex items-center gap-2 text-xs text-gray-400">
      <span>Round</span>
      <div id="dots" class="flex gap-1">{' '.join(f'<div class="dot" id="d{i}"></div>' for i in range(total))}</div>
      <span id="rnd-label">0/{total}</span>
    </div>
    <button onclick="toggleTheme()" id="tbtn"
      class="surface2 border rounded-lg w-8 h-8 flex items-center justify-center text-base hover:opacity-70">☀️</button>
  </div>
</div>

<!-- History -->
<div id="history" class="flex-1 flex flex-col gap-4 px-6 py-6 max-w-2xl w-full mx-auto"></div>

<!-- Result screen (hidden initially) -->
<div id="result" class="hidden flex-1 flex flex-col items-center justify-center gap-4 px-6 py-10 max-w-2xl w-full mx-auto text-center">
  <div id="res-icon" class="text-4xl"></div>
  <div id="res-title" class="text-xl font-bold"></div>
  <div id="res-body" class="text-sm text-gray-500 leading-relaxed"></div>
</div>

<!-- Input area -->
<div id="input-area" class="surface border-t px-6 py-4 sticky bottom-0 shadow-[0_-2px_12px_rgba(0,0,0,.06)]">
  <div class="max-w-2xl mx-auto flex flex-col gap-3">
    <textarea id="ans" rows="4" placeholder="여기에 답변을 입력하세요..."
      class="surface2 border rounded-xl px-4 py-3 text-sm resize-y w-full transition-all"
      oninput="document.getElementById('cc').textContent=this.value.length+'자'"></textarea>
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-3">
        <button id="hint-btn" onclick="showModal('hint')"
          class="text-xs font-semibold px-3 py-1.5 rounded-lg border flex items-center gap-1"
          style="color:var(--blue);background:rgba(59,130,246,.08);border-color:rgba(59,130,246,.25)"
          {'style="display:none"' if mode == 'quiz' else ''}>💡 답 받기</button>
        <button onclick="showModal('giveup')" class="text-xs text-gray-400 hover:text-red-500 transition-colors">포기</button>
      </div>
      <div class="flex items-center gap-3">
        <span id="cc" class="text-xs text-gray-400">0자</span>
        <button onclick="showModal('submit')"
          class="text-sm font-semibold text-white px-5 py-2 rounded-lg flex items-center gap-2 hover:opacity-90 active:scale-95 transition-all"
          style="background:var(--acc)">제출 →</button>
      </div>
    </div>
  </div>
</div>

<!-- Submit modal -->
<div class="overlay" id="m-submit">
  <div class="modal surface border rounded-2xl p-7 w-96 max-w-[90vw] shadow-2xl">
    <div class="text-2xl mb-3">✏️</div>
    <div class="font-bold text-base mb-2">답변을 제출할까요?</div>
    <div class="text-sm text-gray-400 mb-4">제출 후 수정할 수 없습니다.</div>
    <div id="preview" class="surface2 rounded-lg px-3 py-2 text-sm text-gray-400 mb-5 max-h-24 overflow-hidden relative">
      <div class="absolute inset-x-0 bottom-0 h-6" style="background:linear-gradient(transparent,var(--bg,#f1f3f8))"></div>
    </div>
    <div class="flex gap-2 justify-end">
      <button onclick="closeModal('m-submit')" class="surface2 border rounded-lg px-4 py-2 text-sm font-semibold">취소</button>
      <button onclick="doAction('submit')" class="text-white rounded-lg px-4 py-2 text-sm font-semibold" style="background:var(--acc)">제출하기</button>
    </div>
  </div>
</div>

<!-- Hint modal -->
<div class="overlay" id="m-hint">
  <div class="modal surface border rounded-2xl p-7 w-96 max-w-[90vw] shadow-2xl">
    <div class="text-2xl mb-3">💡</div>
    <div class="font-bold text-base mb-2">답을 받을까요?</div>
    <div class="text-sm text-gray-400 mb-5">Claude가 핵심 답변을 알려주고 다음 라운드로 이어집니다.</div>
    <div class="flex gap-2 justify-end">
      <button onclick="closeModal('m-hint')" class="surface2 border rounded-lg px-4 py-2 text-sm font-semibold">취소</button>
      <button onclick="doAction('hint')" class="text-white rounded-lg px-4 py-2 text-sm font-semibold" style="background:var(--blue)">답 보기</button>
    </div>
  </div>
</div>

<!-- Giveup modal -->
<div class="overlay" id="m-giveup">
  <div class="modal surface border rounded-2xl p-7 w-96 max-w-[90vw] shadow-2xl">
    <div class="text-2xl mb-3">🏳️</div>
    <div class="font-bold text-base mb-2">세션을 포기할까요?</div>
    <div class="text-sm text-gray-400 mb-5">갭이 <strong>weak</strong>으로 저장되고 세션이 종료됩니다.</div>
    <div class="flex gap-2 justify-end">
      <button onclick="closeModal('m-giveup')" class="surface2 border rounded-lg px-4 py-2 text-sm font-semibold">계속하기</button>
      <button onclick="doAction('giveup')" class="bg-red-500 text-white rounded-lg px-4 py-2 text-sm font-semibold">포기하기</button>
    </div>
  </div>
</div>

<script>
const MODE='{mode}', TOTAL={total}, SHOW_HINT={show_hint};
let history=[], curRound=0, waiting=false;

// Theme
function toggleTheme(){{
  const h=document.documentElement;
  const d=h.getAttribute('data-theme')==='dark';
  h.setAttribute('data-theme',d?'light':'dark');
  document.getElementById('tbtn').textContent=d?'☀️':'🌙';
}}

// Dots
function updateDots(r){{
  for(let i=0;i<TOTAL;i++){{
    const d=document.getElementById('d'+i);
    if(!d)continue;
    d.className='dot'+(i<r-1?' done':i===r-1?' cur':'');
  }}
  document.getElementById('rnd-label').textContent=r+'/'+TOTAL;
}}

// History render
function renderHistory(){{
  const el=document.getElementById('history');
  el.innerHTML=history.map((h,i)=>{{
    const isCur=(h.role==='q'&&i===history.length-1&&!waiting);
    const isLastQ=(h.role==='q'&&i===history.length-1);
    if(h.role==='q'){{
      return `<div class="bubble-q${{isCur?' current':''}} border rounded-xl p-4 self-start max-w-[88%]">
        <div class="text-[10px] font-bold uppercase tracking-widest mb-2" style="color:var(--acc)">Q${{h.round}}</div>
        <div class="text-sm leading-relaxed">${{h.text}}</div>
      </div>`;
    }} else {{
      return `<div class="bubble-a border rounded-xl p-4 self-end max-w-[85%]">
        <div class="text-[10px] font-bold uppercase tracking-widest mb-2" style="color:var(--blue)">A${{h.round}}</div>
        <div class="text-sm leading-relaxed">${{h.text}}</div>
      </div>`;
    }}
  }}).join('');
  el.scrollTop=el.scrollHeight;
}}

// Polling
async function poll(){{
  try{{
    const res=await fetch('/question');
    const q=await res.json();
    if(!q.round)return;

    // New question arrived
    if(q.round>curRound){{
      curRound=q.round;
      history.push({{role:'q',round:q.round,text:q.text}});
      updateDots(q.round);
      renderHistory();
      setWaiting(false);
    }}

    // Session ended
    if(q.status==='complete'||q.status==='aborted'){{
      showResult(q);
    }}
  }}catch(e){{}}
}}

setInterval(poll,1000);

function setWaiting(v){{
  waiting=v;
  document.getElementById('input-area').style.opacity=v?'0.4':'1';
  document.getElementById('input-area').style.pointerEvents=v?'none':'all';
}}

// Modals
function showModal(type){{
  if(type==='submit'){{
    const v=document.getElementById('ans').value.trim();
    if(!v){{
      document.getElementById('ans').style.borderColor='#ef4444';
      setTimeout(()=>document.getElementById('ans').style.borderColor='',900);
      return;
    }}
    document.getElementById('preview').childNodes[0] && 
      (document.getElementById('preview').firstChild.textContent=v);
    document.getElementById('preview').textContent=v;
  }}
  document.getElementById('m-'+type).classList.add('show');
}}
function closeModal(id){{document.getElementById(id).classList.remove('show');}}
document.querySelectorAll('.overlay').forEach(el=>
  el.addEventListener('click',e=>{{if(e.target===el)el.classList.remove('show');}})
);

async function doAction(action){{
  const ans=document.getElementById('ans').value.trim();
  closeModal('m-'+action);
  closeModal('m-submit');
  closeModal('m-hint');
  closeModal('m-giveup');

  const displayText = action==='submit'?ans : action==='hint'?'💡 답 받기 요청':'🏳️ 포기';
  history.push({{role:'a',round:curRound,text:displayText}});
  renderHistory();
  setWaiting(true);

  document.getElementById('ans').value='';
  document.getElementById('cc').textContent='0자';

  await fetch('/answer',{{
    method:'POST',
    headers:{{'Content-Type':'application/json'}},
    body:JSON.stringify({{action,answer:ans}})
  }});
}}

function showResult(q){{
  document.getElementById('input-area').style.display='none';
  document.getElementById('history').style.display='none';
  document.getElementById('result').classList.remove('hidden');
  document.getElementById('result').classList.add('flex');

  const ok=q.status==='complete';
  document.getElementById('res-icon').textContent=ok?'✅':'🏳️';
  document.getElementById('res-title').textContent=ok
    ?'Feynman 검증 통과!'
    :'세션 중단';

  const r=q.result||{{}};
  let body='';
  if(r.weak&&r.weak.length)
    body+=`<p class="mb-2">약점: ${{r.weak.join(', ')}}</p>`;
  if(r.score!==undefined)
    body+=`<p class="mb-2">점수: ${{r.score}}/${{TOTAL}}</p>`;
  body+=`<p class="mt-4 text-xs font-mono surface2 p-2 rounded">/ax-study quiz</p>`;
  document.getElementById('res-body').innerHTML=body;
}}
</script>
</body>
</html>"""


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    global _args, HTML

    parser = argparse.ArgumentParser(description="AX Feynman/Quiz web server")
    parser.add_argument("--mode", required=True, choices=["feynman", "quiz"])
    parser.add_argument("--concept", default="")
    parser.add_argument("--total", type=int, default=5)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--q-file", required=True, dest="q_file")
    parser.add_argument("--pipe", required=True)
    parser.add_argument("--port-file", required=True, dest="port_file")
    _args = parser.parse_args()

    HTML = build_html(_args.mode, _args.concept, _args.total)

    # Start server on dynamic port
    from werkzeug.serving import make_server
    server = make_server("127.0.0.1", _args.port, app, threaded=True)
    port = server.server_address[1]
    Path(_args.port_file).write_text(str(port))

    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/ax-docs-changelog/bin/ax-feynman-server.py
```

Wait — 이 task는 main repo가 아닌 worktree에서 작업한다. 워크트리를 먼저 생성한다:

```bash
# main repo에서 실행
git -C /home/jin/.claude/plugins/marketplaces/ax-claude checkout -b feat/feynman-web-ui
# 이미 main에 있으면:
git -C /home/jin/.claude/plugins/marketplaces/ax-claude branch feat/feynman-web-ui
git -C /home/jin/.claude/plugins/marketplaces/ax-claude worktree add ~/ax-feynman-web ~/ax-feynman-web-branch
# 실제 명령:
git -C /home/jin/.claude/plugins/marketplaces/ax-claude worktree add ~/ax-feynman-web feat/feynman-web-ui
```

파일은 `~/ax-feynman-web/bin/ax-feynman-server.py`에 생성한다.

- [ ] **Step 3: 실행 권한 부여**

```bash
chmod +x ~/ax-feynman-web/bin/ax-feynman-server.py
```

- [ ] **Step 4: Flask 설치 및 서버 기동 스모크 테스트**

```bash
pip install flask --quiet

# q-file과 pipe 준비
Q_FILE=$(mktemp /tmp/ax-test-q.XXXX.json)
PIPE_FILE=/tmp/ax-test.pipe
PORT_FILE=$(mktemp /tmp/ax-test-port.XXXX)
rm -f "$PIPE_FILE" && mkfifo "$PIPE_FILE"

printf '{"mode":"feynman","concept":"Test","round":1,"total":5,"text":"Q1 test","status":"active","result":{"score":null,"weak":[]}}' > "$Q_FILE"

python3 ~/ax-feynman-web/bin/ax-feynman-server.py \
  --mode feynman --concept "Test" --total 5 \
  --port 0 --q-file "$Q_FILE" --pipe "$PIPE_FILE" --port-file "$PORT_FILE" &
SERVER_PID=$!

sleep 0.5
PORT=$(cat "$PORT_FILE")
echo "Server on port: $PORT"

# /question endpoint 확인
curl -s "http://localhost:$PORT/question" | python3 -m json.tool
# Expected: {"mode":"feynman","concept":"Test","round":1,...}

# /shutdown
curl -s "http://localhost:$PORT/shutdown"
sleep 0.3
rm -f "$Q_FILE" "$PIPE_FILE" "$PORT_FILE"
echo "PASS: server started, /question works, /shutdown works"
```

Expected output:
```
Server on port: <port>
{
    "concept": "Test",
    "mode": "feynman",
    "round": 1,
    ...
}
bye
PASS: server started, /question works, /shutdown works
```

- [ ] **Step 5: /answer endpoint 테스트**

```bash
Q_FILE=$(mktemp /tmp/ax-test-q.XXXX.json)
PIPE_FILE=/tmp/ax-test2.pipe
PORT_FILE=$(mktemp /tmp/ax-test-port.XXXX)
rm -f "$PIPE_FILE" && mkfifo "$PIPE_FILE"
printf '{"mode":"feynman","concept":"Test","round":1,"total":5,"text":"Q1","status":"active","result":{"score":null,"weak":[]}}' > "$Q_FILE"

python3 ~/ax-feynman-web/bin/ax-feynman-server.py \
  --mode feynman --concept "Test" --total 5 \
  --port 0 --q-file "$Q_FILE" --pipe "$PIPE_FILE" --port-file "$PORT_FILE" &
SERVER_PID=$!
sleep 0.5
PORT=$(cat "$PORT_FILE")

# POST /answer → pipe에서 읽기 (background로 읽기)
(read LINE < "$PIPE_FILE" && echo "Pipe received: $LINE") &

curl -s -X POST "http://localhost:$PORT/answer" \
  -H "Content-Type: application/json" \
  -d '{"action":"submit","answer":"This is my answer"}'
# Expected: {"ok": true}

sleep 0.3
# Background reader가 "Pipe received: submit:This is my answer" 출력해야 함

curl -s "http://localhost:$PORT/shutdown"
rm -f "$Q_FILE" "$PIPE_FILE" "$PORT_FILE"
```

Expected:
```
{"ok":true}
Pipe received: submit:This is my answer
```

- [ ] **Step 6: 커밋**

```bash
git -C ~/ax-feynman-web add bin/ax-feynman-server.py
git -C ~/ax-feynman-web commit -m "feat: add ax-feynman-server.py — Flask web UI for Feynman+Quiz modes"
```

---

## Task 2: SKILL.md — Feynman Mode 서버 통합

**Files:**
- Modify: `skills/ax-study/SKILL.md` (Feynman Mode section, lines ~606–770)

현재 Feynman Mode는 터미널에서 사용자 답변을 대기한다. 다음과 같이 변경한다:
- Step 1 앞에 **Step 0: 웹 서버 기동** 추가
- Step 2: q-file에 Q1 기록 → pipe에서 답변 읽기 (터미널 대기 제거)
- Step 4: q-file에 Q{N} 기록 → pipe에서 답변 읽기
- Step 5-A/5-B: q-file status 업데이트 → /shutdown 호출

- [ ] **Step 1: Feynman Mode에 Step 0 삽입**

`skills/ax-study/SKILL.md`의 `## Feynman Mode` 섹션에서 `### Step 1: 컨텍스트 로드 및 개념명 확인` 바로 앞에 다음 내용을 삽입한다:

```markdown
### Step 0: 웹 서버 기동

```bash
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
xdg-open "http://localhost:$AX_PORT" 2>/dev/null || \
  open "http://localhost:$AX_PORT" 2>/dev/null || true
echo "🌐 Feynman UI: http://localhost:$AX_PORT"
```

CONCEPT 변수는 사용자가 입력한 개념명으로, Step 1 이전에 이미 결정되어 있어야 한다.
서버 기동 실패(python3 없거나 flask 미설치) 시: "웹 서버 실행 실패. pip install flask 후 재시도하세요." 출력 후 종료.
```

- [ ] **Step 2: Step 2 (라운드 1) 수정 — q-file 기록 + pipe 읽기**

기존 Step 2 내용:
```markdown
다음 메시지 출력 후 사용자 답변 대기:

\```
=== AX Study: Feynman — {개념명} ===

'{개념명}'을 초등학생에게 설명한다고 가정하고 설명해보세요. [1/5]
\```
```

를 아래로 교체한다:

```markdown
Q1 텍스트를 q-file에 기록하고 브라우저에 표시한다:

\```bash
Q1_TEXT="${CONCEPT}을 초등학생에게 설명한다고 가정하고 설명해보세요."
printf '{"mode":"feynman","concept":"%s","round":1,"total":%d,"text":"%s","status":"active","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_TOTAL" "$Q1_TEXT" > "$AX_Q_FILE"
\```

터미널에도 출력:
\```
=== AX Study: Feynman — {개념명} ===

브라우저(http://localhost:{AX_PORT})에서 답변을 입력하고 제출하세요. [1/5]
\```

pipe에서 사용자 답변 대기 (브라우저 제출 시 자동 수신):
\```bash
AX_LINE=$(cat "$AX_PIPE")
AX_ACTION="${AX_LINE%%:*}"   # submit | hint | giveup
AX_ANSWER="${AX_LINE#*:}"
\```

- `AX_ACTION=submit` → AX_ANSWER를 사용자 설명으로 사용, Step 3으로
- `AX_ACTION=hint` → Step 3 갭 탐지 없이 Claude가 Q1 핵심 답변 출력 → 다음 라운드 진행  
- `AX_ACTION=giveup` → Step 5-B로
```

- [ ] **Step 3: Step 4 (라운드 2~5) 수정 — q-file + pipe 패턴**

기존 Step 4의 "사용자 답변 대기 → 다시 Step 3으로." 부분을 아래로 교체한다:

```markdown
다음 질문을 q-file에 기록:
\```bash
QN_TEXT="{갭 기반 소크라테스 질문 텍스트}"
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"%s","status":"active","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_CURRENT_ROUND" "$AX_TOTAL" "$QN_TEXT" > "$AX_Q_FILE"
\```

pipe에서 답변 대기:
\```bash
AX_LINE=$(cat "$AX_PIPE")
AX_ACTION="${AX_LINE%%:*}"
AX_ANSWER="${AX_LINE#*:}"
\```

- `AX_ACTION=submit` → 답변으로 다시 Step 3
- `AX_ACTION=hint` → 현재 갭 답변 출력 후 다음 라운드
- `AX_ACTION=giveup` → Step 5-B
```

- [ ] **Step 4: Step 5-A (완료) 끝에 서버 종료 추가**

기존 Step 5-A 마지막에 추가:

```markdown
q-file status를 complete로 업데이트하고 서버를 종료한다:
\```bash
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"완료","status":"complete","result":{"score":null,"weak":[]}}' \
  "$CONCEPT" "$AX_CURRENT_ROUND" "$AX_TOTAL" > "$AX_Q_FILE"
sleep 1
curl -s "http://localhost:$AX_PORT/shutdown" >/dev/null 2>&1 || true
rm -f "$AX_Q_FILE" "$AX_PIPE" "$AX_PORT_FILE"
\```
```

- [ ] **Step 5: Step 5-B (중단) 끝에 서버 종료 추가**

기존 Step 5-B 마지막에 추가:

```markdown
q-file status를 aborted로 업데이트하고 서버를 종료한다:
\```bash
# Claude: WEAK_LIST에 실제 약점 개념 목록 (쉼표 구분)을 넣는다
WEAK_LIST="약점1,약점2"
printf '{"mode":"feynman","concept":"%s","round":%d,"total":%d,"text":"중단","status":"aborted","result":{"score":null,"weak":["%s"]}}' \
  "$CONCEPT" "$AX_CURRENT_ROUND" "$AX_TOTAL" "$WEAK_LIST" > "$AX_Q_FILE"
sleep 1
curl -s "http://localhost:$AX_PORT/shutdown" >/dev/null 2>&1 || true
rm -f "$AX_Q_FILE" "$AX_PIPE" "$AX_PORT_FILE"
\```
```

- [ ] **Step 6: 커밋**

```bash
git -C ~/ax-feynman-web add skills/ax-study/SKILL.md
git -C ~/ax-feynman-web commit -m "feat(study): integrate web server into Feynman Mode"
```

---

## Task 3: SKILL.md — Quiz Mode 서버 통합

**Files:**
- Modify: `skills/ax-study/SKILL.md` (Quiz Mode section, lines ~459–604)

- [ ] **Step 1: Quiz Mode Step 1 앞에 Step 0 삽입**

`### Step 1: 컨텍스트 로드` 바로 앞에 삽입:

```markdown
### Step 0: 웹 서버 기동

\```bash
AX_PID=$$
AX_Q_FILE="/tmp/ax-feynman-${AX_PID}-q.json"
AX_PIPE="/tmp/ax-feynman-${AX_PID}.pipe"
AX_PORT_FILE="/tmp/ax-feynman-${AX_PID}-port.txt"
AX_TOTAL="${N:-5}"

rm -f "$AX_PIPE" && mkfifo "$AX_PIPE"

printf '{"mode":"quiz","concept":"","round":0,"total":%d,"text":"","status":"starting","result":{"score":null,"weak":[]}}' \
  "$AX_TOTAL" > "$AX_Q_FILE"

python3 "$PLUGIN_ROOT/bin/ax-feynman-server.py" \
  --mode quiz \
  --total "$AX_TOTAL" \
  --port 0 \
  --q-file "$AX_Q_FILE" \
  --pipe "$AX_PIPE" \
  --port-file "$AX_PORT_FILE" &
AX_SERVER_PID=$!

sleep 0.5
AX_PORT=$(cat "$AX_PORT_FILE" 2>/dev/null || echo "5000")
xdg-open "http://localhost:$AX_PORT" 2>/dev/null || \
  open "http://localhost:$AX_PORT" 2>/dev/null || true
echo "🌐 Quiz UI: http://localhost:$AX_PORT"
\```
```

- [ ] **Step 2: Step 3 (퀴즈 세션) 수정 — q-file + pipe 패턴**

기존 Step 3의 "사용자 답변 후 평가" 루프를 다음 패턴으로 교체한다:

```markdown
각 문제마다:

1. 문제를 q-file에 기록:
\```bash
# AX_QNUM: 현재 문제 번호 (1부터), AX_QTEXT: 질문 텍스트
printf '{"mode":"quiz","concept":"","round":%d,"total":%d,"text":"%s","status":"active","result":{"score":null,"weak":[]}}' \
  "$AX_QNUM" "$AX_TOTAL" "$AX_QTEXT" > "$AX_Q_FILE"
\```

2. 터미널 출력:
\```
**Q{AX_QNUM}/{AX_TOTAL}: {질문}** (브라우저에서 답변)
\```

3. pipe에서 답변 대기:
\```bash
AX_LINE=$(cat "$AX_PIPE")
AX_ACTION="${AX_LINE%%:*}"
AX_ANSWER="${AX_LINE#*:}"
\```

4. `AX_ACTION=giveup` → 즉시 Step 4로 (세션 종료)
5. `AX_ACTION=submit` → Claude가 AX_ANSWER를 채점 후 다음 문제
```

- [ ] **Step 3: Step 4 (결과) 끝에 서버 종료 추가**

기존 Step 4 마지막에 추가:

```markdown
q-file status를 complete로 업데이트하고 서버를 종료한다:
\```bash
# Claude: SCORE=정답수, WEAK_LIST="약점1,약점2"
SCORE=0; WEAK_LIST=""
printf '{"mode":"quiz","concept":"","round":%d,"total":%d,"text":"완료","status":"complete","result":{"score":%d,"weak":["%s"]}}' \
  "$AX_TOTAL" "$AX_TOTAL" "$SCORE" "$WEAK_LIST" > "$AX_Q_FILE"
sleep 1
curl -s "http://localhost:$AX_PORT/shutdown" >/dev/null 2>&1 || true
rm -f "$AX_Q_FILE" "$AX_PIPE" "$AX_PORT_FILE"
\```
```

- [ ] **Step 4: 커밋**

```bash
git -C ~/ax-feynman-web add skills/ax-study/SKILL.md
git -C ~/ax-feynman-web commit -m "feat(study): integrate web server into Quiz Mode"
```

---

## Task 4: setup + 버전 범프 + CHANGELOG + README

**Files:**
- Modify: `setup`
- Modify: `VERSION`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: setup에 Flask 설치 추가**

`~/ax-feynman-web/setup` 파일을 읽어 `pip install pyyaml` 라인 근처에 다음 줄을 추가한다:

```bash
pip install flask --quiet 2>/dev/null || pip3 install flask --quiet 2>/dev/null || \
  echo "Warning: flask install failed. Run: pip install flask"
```

- [ ] **Step 2: VERSION 1.19.0으로 업데이트**

```bash
echo "1.19.0" > ~/ax-feynman-web/VERSION
```

- [ ] **Step 3: plugin.json version 업데이트**

`~/ax-feynman-web/.claude-plugin/plugin.json`의 `"version"` 필드를 `"1.19.0"`으로 변경.

- [ ] **Step 4: marketplace.json version 업데이트 (2곳)**

`~/ax-feynman-web/.claude-plugin/marketplace.json`의 두 `"version"` 필드를 `"1.19.0"`으로 변경.

- [ ] **Step 5: CHANGELOG.md에 v1.19.0 항목 추가**

`CHANGELOG.md` 상단(첫 `##` 항목 앞)에 추가:

```markdown
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

```

- [ ] **Step 6: README.md ax-study 섹션에 웹 UI 안내 추가**

`README.md`의 `/ax-study quiz [N]` 줄 아래에 추가:

```markdown
> **v1.19+**: `feynman`과 `quiz` 명령 실행 시 로컬 브라우저 UI 자동 오픈.
> Light/Dark 모드 지원. 답변을 터미널 대신 브라우저에서 입력.
```

- [ ] **Step 7: 커밋**

```bash
git -C ~/ax-feynman-web add setup VERSION .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json CHANGELOG.md README.md
git -C ~/ax-feynman-web commit -m "chore: bump version to 1.19.0, update CHANGELOG and README"
```

---

## Self-Review

**Spec coverage:**
- ✅ `/ax-study feynman` → 브라우저 자동 오픈 (Step 0 in Task 2)
- ✅ `/ax-study quiz` → 브라우저 자동 오픈 (Step 0 in Task 3)
- ✅ GET /question polling (Task 1 server)
- ✅ POST /answer → named pipe (Task 1 server)
- ✅ 세션 종료 시 서버 자동 종료 (Step 4/5 in Tasks 2 & 3)
- ✅ 제출/답받기/포기 모달 (Task 1 HTML)
- ✅ Light/Dark toggle (Task 1 HTML)
- ✅ setup Flask 설치 (Task 4)
- ✅ VERSION 1.19.0 (Task 4)

**Non-goals 확인:**
- Concept 모드 웹 UI 없음 ✅
- 원격 접속(0.0.0.0 바인딩) 없음 — localhost only ✅
