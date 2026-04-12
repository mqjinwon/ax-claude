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
    except Exception as e:
        print(f"read_q error: {e}", file=sys.stderr)
        return {}


def write_pipe(line: str):
    with _lock:
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
          style="color:var(--blue);background:rgba(59,130,246,.08);border-color:rgba(59,130,246,.25){';display:none' if mode == 'quiz' else ''}">💡 답 받기</button>
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
  function esc(s){{const d=document.createElement('div');d.textContent=String(s);return d.innerHTML;}}
  let body='';
  if(r.weak&&r.weak.length)
    body+=`<p class="mb-2">약점: ${{r.weak.map(esc).join(', ')}}</p>`;
  if(r.score!==undefined&&r.score!==null)
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
