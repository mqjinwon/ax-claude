#!/usr/bin/env python3
# ax-guide.py — Print full skill guide from skill-routing.yaml
# Usage: python3 ax-guide.py <routing_yaml_path>
# Env:   AX_ROUTING=<path>  (alternative to positional arg)

import yaml, os, sys

ROUTING_PATH = (
    sys.argv[1] if len(sys.argv) > 1
    else os.environ.get("AX_ROUTING")
    or os.path.expanduser("~/.ax/routing/skill-routing.yaml")
)

with open(ROUTING_PATH) as f:
    data = yaml.safe_load(f)

hidden = set(data.get("hidden", []))
cats = data.get("categories", {})

print("=== AX Skill Guide ===\n")
print("사용 방법")
print("  /ax              → 세션 컨텍스트 요약 (resume)")
print("  /ax <작업 설명>  → 적합한 스킬 추천 (routing)")
print("  /ax learn        → 이 가이드")
print("  /ax learn <내용> → 인사이트 저장 → MEMORY.md\n")

print("─" * 60)
print("라우팅 카테고리\n")
for cat, info in cats.items():
    canonical = info.get("canonical", "")
    orchestrator = info.get("orchestrator", "")
    triggers = info.get("trigger", [])[:3]
    orch_triggers = info.get("orchestrator_trigger", [])[:2]
    trigger_str = " · ".join(f'"{t}"' for t in triggers)
    line = f"  {cat:<25} → {canonical}"
    if orchestrator:
        line += f"\n  {'':25}   (전체: {orchestrator})"
    print(line)
    if trigger_str:
        print(f"  {'':25}   트리거: {trigger_str}")
    if orch_triggers:
        orch_str = " · ".join(f'"{t}"' for t in orch_triggers)
        print(f"  {'':25}   전체트리거: {orch_str}")
    print()

print("─" * 60)
print("숨김 처리된 스킬 (직접 호출은 가능)")
print("  " + ", ".join(sorted(hidden)))
