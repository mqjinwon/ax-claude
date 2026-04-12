#!/usr/bin/env python3
# ax-learn.py — Analyze routing-log.jsonl → generate routing-suggestions.md
# Usage: python3 ax-learn.py <project_root> [<routing_yaml_path>]

import datetime
import difflib
import json
import os
import re
import sys
from collections import defaultdict

# ── Args ──────────────────────────────────────────────────────────────────────
PROJECT_ROOT = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PROJECT_ROOT", ".")
ROUTING_PATH = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("AX_ROUTING", "")

LOG_PATH = os.path.join(PROJECT_ROOT, ".ax", "routing-log.jsonl")
SUGGESTIONS_PATH = os.path.join(PROJECT_ROOT, ".ax", "memory", "routing-suggestions.md")

if not os.path.exists(LOG_PATH):
    sys.exit(0)

# ── Load YAML (dedup against known triggers/examples) ─────────────────────────
known_triggers: dict = defaultdict(set)
known_examples: dict = defaultdict(set)
if ROUTING_PATH and os.path.exists(ROUTING_PATH):
    import yaml
    with open(ROUTING_PATH) as f:
        try:
            data = yaml.safe_load(f) or {}
        except yaml.YAMLError:
            data = {}
    for cat, info in data.get("categories", {}).items():
        for t in info.get("trigger", []) + info.get("orchestrator_trigger", []):
            known_triggers[cat].add(t.lower())
        for e in info.get("examples", []):
            known_examples[cat].add(e.lower())

# ── Parse log ─────────────────────────────────────────────────────────────────
matched: dict = defaultdict(list)
unmatched: list = []

with open(LOG_PATH) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        prompt = entry.get("prompt", "")
        if not prompt:
            continue
        cat = entry.get("category")
        if cat:
            matched[cat].append(prompt)
        else:
            unmatched.append(prompt)

# ── Examples candidates (matched prompts not already known) ───────────────────
examples_candidates: dict = {}
for cat, prompts in matched.items():
    seen: set = set()
    candidates = []
    for p in prompts:
        pl = p.lower()
        if pl not in known_examples[cat] and pl not in seen:
            seen.add(pl)
            candidates.append(p)
            if len(candidates) >= 3:
                break
    if candidates:
        examples_candidates[cat] = candidates

# ── Trigger candidates (unmatched → best fuzzy guess) ─────────────────────────
trigger_candidates = []
all_triggers_flat = [
    (cat, t)
    for cat, triggers in known_triggers.items()
    for t in triggers
]
for prompt in unmatched[:50]:
    best_cat, best_score = None, 0.0
    for cat, t in all_triggers_flat:
        score = difflib.SequenceMatcher(None, prompt.lower(), t).ratio()
        if score > best_score:
            best_score, best_cat = score, cat
    if best_cat and best_score >= 0.40:
        trigger_candidates.append((prompt, best_cat, best_score))
    else:
        trigger_candidates.append((prompt, best_cat or "?", best_score))

# ── Build suggestions content ─────────────────────────────────────────────────
today = datetime.date.today().isoformat()
lines = [
    "<!-- BEGIN:routing-suggestions -->",
    f"## {today} 라우팅 분석",
    "",
    "### Examples 추가 후보",
    "| 카테고리 | 프롬프트 | 액션 |",
    "|---|---|---|",
]
if examples_candidates:
    for cat, prompts in examples_candidates.items():
        for p in prompts:
            p_safe = p.replace("|", "\\|").replace("\n", " ").replace("\r", "").replace("\t", " ")
            lines.append(f'| {cat} | "{p_safe}" | `/ax learn` 또는 수동 추가 |')
else:
    lines.append("| — | (없음) | — |")

lines += [
    "",
    "### 새 Trigger 후보 (미매칭)",
    "| 프롬프트 | 추정 카테고리 | 유사도 |",
    "|---|---|---|",
]
if trigger_candidates:
    for prompt, cat, score in trigger_candidates:
        p_safe = prompt.replace("|", "\\|").replace("\n", " ").replace("\r", "").replace("\t", " ")
        lines.append(f'| "{p_safe}" | {cat} | {score:.2f} |')
else:
    lines.append("| — | (없음) | — |")

lines += ["<!-- END:routing-suggestions -->"]
new_section = "\n".join(lines)

# ── Write/update suggestions file ─────────────────────────────────────────────
os.makedirs(os.path.dirname(SUGGESTIONS_PATH), exist_ok=True)

if os.path.exists(SUGGESTIONS_PATH):
    with open(SUGGESTIONS_PATH) as f:
        existing = f.read()
    pattern = r'<!-- BEGIN:routing-suggestions -->.*?<!-- END:routing-suggestions -->'
    if re.search(pattern, existing, flags=re.DOTALL):
        updated = re.sub(pattern, new_section, existing, count=1, flags=re.DOTALL)
    else:
        # Section not found — append
        updated = existing.rstrip("\n") + "\n\n" + new_section + "\n"
    with open(SUGGESTIONS_PATH, "w") as f:
        f.write(updated)
else:
    with open(SUGGESTIONS_PATH, "w") as f:
        f.write(new_section + "\n")

print(f"routing-suggestions.md updated: {SUGGESTIONS_PATH}", file=sys.stderr)
