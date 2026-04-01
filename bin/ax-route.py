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

import yaml, sys, os

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

# Check orchestrator_trigger first (longer/more specific matches win)
for cat, info in data.get("categories", {}).items():
    if info.get("canonical") in hidden:
        continue
    orch_triggers = sorted(info.get("orchestrator_trigger", []), key=len, reverse=True)
    for t in orch_triggers:
        if t.lower() in inp.lower():
            print(f"MATCH={cat}")
            print(f"CANONICAL={info.get('orchestrator', info['canonical'])}")
            print(f"MODE=orchestrator")
            sys.exit(0)

# Then check canonical trigger
for cat, info in data.get("categories", {}).items():
    if info.get("canonical") in hidden:
        continue
    triggers = sorted(info.get("trigger", []), key=len, reverse=True)
    for t in triggers:
        if t.lower() in inp.lower():
            print(f"MATCH={cat}")
            print(f"CANONICAL={info['canonical']}")
            orch = info.get("orchestrator", "")
            if orch:
                print(f"ORCHESTRATOR={orch}")
            print(f"MODE=canonical")
            sys.exit(0)
