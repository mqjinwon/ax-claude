#!/usr/bin/env python3
# ax-route.py — Match user input to canonical skill via skill-routing.yaml
# Usage: python3 ax-route.py "<user input>" [<routing_yaml_path>]
# Env:   AX_ROUTING=<path>  (alternative to positional 2nd arg)
#
# Output (one per line, only present fields):
#   MATCH=<category>
#   CANONICAL=<skill>
#   MODE=orchestrator|canonical
#   ORCHESTRATOR=<skill>   (only when MODE=canonical and orchestrator exists)
#   CONFIDENCE=0.xx        (Tier 2/3 only)
#   SOURCE=fuzzy|tfidf     (Tier 2/3 only)
#
# Exits 0 with empty output if no match or informational query.

import difflib
import math
import os
import re
import sys
from collections import Counter

import yaml

# ── Args / YAML load ──────────────────────────────────────────────────────────
if len(sys.argv) < 2:
    sys.exit(0)

inp = sys.argv[1]
ROUTING_PATH = (
    sys.argv[2] if len(sys.argv) > 2
    else os.environ.get("AX_ROUTING")
    or os.path.expanduser("~/.ax/routing/skill-routing.yaml")
)

with open(ROUTING_PATH) as f:
    data = yaml.safe_load(f)

hidden = set(data.get("hidden", []))
categories = data.get("categories", {})

# ── Sanitize ──────────────────────────────────────────────────────────────────
def sanitize(text: str) -> str:
    text = re.sub(r'<!--[\s\S]*?-->', '', text)
    text = re.sub(r'```[\s\S]*?```', '', text)
    text = re.sub(r'`[^`]+`', '', text)
    text = re.sub(r'https?://\S+', '', text)
    text = re.sub(r'^\s*>.*$', '', text, flags=re.M)
    return text

# ── Tier 0: Informational Filter ──────────────────────────────────────────────
INFORMATIONAL_PATTERNS = [
    re.compile(
        r"\b(?:what(?:'s|\s+is)|what\s+are|how\s+(?:to|do\s+i)\s+use|"
        r"explain|tell\s+me\s+about|describe)\b", re.I
    ),
    re.compile(
        r'(?:뭐야|뭔데|무엇(?:이야|인가요)?|어떤\s*기능|기능\s*(?:알려|설명|뭐)|'
        r'설명해\s?줘|어떤\s*건데|그게\s*뭐|이게\s*뭔|어떻게\s*(?:쓰|사용|작동))',
        re.U,
    ),
]
ACTION_OVERRIDE = re.compile(
    r'(?:써줘|(?<![가-힣])해줘|만들어|시작해|돌려|구현해|배포해|push|run|start|deploy|ship|fix)',
    re.I | re.U,
)

def is_informational(text: str) -> bool:
    if ACTION_OVERRIDE.search(text):
        return False
    return any(p.search(text) for p in INFORMATIONAL_PATTERNS)

clean = sanitize(inp)
if is_informational(clean):
    sys.exit(0)

inp_lower = clean.lower()

# ── Tier 1: Exact keyword match ───────────────────────────────────────────────
def requires_word_boundaries(trigger: str) -> bool:
    return any(ch.isascii() and ch.isalnum() for ch in trigger)

def has_word_boundaries(text: str, start: int, end: int) -> bool:
    before = text[start - 1] if start > 0 else ""
    after = text[end] if end < len(text) else ""
    before_ok = not before or not (before.isascii() and before.isalnum())
    after_ok = not after or not (after.isascii() and after.isalnum())
    return before_ok and after_ok

def iter_match_indexes(text: str, trigger: str):
    start = 0
    while True:
        idx = text.find(trigger, start)
        if idx == -1:
            return
        yield idx
        start = idx + 1

best_match = None
for category_index, (cat, info) in enumerate(categories.items()):
    if info.get("canonical") in hidden:
        continue
    for mode, triggers in (
        ("orchestrator", info.get("orchestrator_trigger", [])),
        ("canonical", info.get("trigger", [])),
    ):
        for trigger_index, trigger in enumerate(triggers):
            lowered_trigger = trigger.lower()
            for match_index in iter_match_indexes(inp_lower, lowered_trigger):
                if requires_word_boundaries(lowered_trigger):
                    end_index = match_index + len(lowered_trigger)
                    if not has_word_boundaries(inp_lower, match_index, end_index):
                        continue
                candidate = (
                    len(lowered_trigger),
                    1 if mode == "orchestrator" else 0,
                    -match_index,
                    -category_index,
                    -trigger_index,
                    cat,
                    info,
                    mode,
                )
                if best_match is None or candidate > best_match:
                    best_match = candidate

if best_match is not None:
    _, _, _, _, _, cat, info, mode = best_match
    print(f"MATCH={cat}")
    if mode == "orchestrator":
        print(f"CANONICAL={info.get('orchestrator', info['canonical'])}")
        print("MODE=orchestrator")
    else:
        print(f"CANONICAL={info['canonical']}")
        orch = info.get("orchestrator", "")
        if orch:
            print(f"ORCHESTRATOR={orch}")
        print("MODE=canonical")
    sys.exit(0)

# ── Tier 2: Fuzzy match (Task 3 추가 예정) ────────────────────────────────────
# ── Tier 3: TF-IDF match (Task 4 추가 예정) ───────────────────────────────────
sys.exit(0)
