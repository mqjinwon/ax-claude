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
#
# Exits 0 with empty output if no match.

import os
import sys

import yaml

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
inp_lower = inp.lower()
best_match = None


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
        match_index = text.find(trigger, start)
        if match_index == -1:
            return
        yield match_index
        start = match_index + 1

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
