
#!/usr/bin/env python3
"""Run all problem-solving fixer agents and produce a merged report."""
import sys
import json
from pathlib import Path

root = Path(r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem")
sys.path.insert(0, str(root))

from src.agents.fixers.docker_fixer import DockerFixer
from src.agents.fixers.codex_plugin_fixer import CodexPluginFixer
from src.agents.fixers.auth_fixer import AuthFixer
from src.agents.fixers.service_fixer import ServiceFixer
from src.agents.fixers.network_fixer import NetworkFixer
from src.agents.fixers.vs_project_fixer import VsProjectFixer

agents = [
    DockerFixer(root / "memory"),
    CodexPluginFixer(root / "memory"),
    AuthFixer(root / "memory"),
    ServiceFixer(root / "memory"),
    NetworkFixer(root / "memory"),
    VsProjectFixer(root / "memory"),
]

results = []
for agent in agents:
    print(f"\n=== Running {agent.name} ===")
    try:
        result = agent.run()
        results.append(result.to_dict())
        print(f"Status: {result.status}")
        for f in result.findings: print(f"  FIND: {f}")
        for a in result.actions: print(f"  ACTION: {a}")
        for e in result.errors: print(f"  ERROR: {e}")
        for r in result.recommendations: print(f"  REC: {r}")
    except Exception as e:
        err = {"agent": agent.name, "status": "failed", "errors": [str(e)]}
        results.append(err)
        print(f"EXCEPTION: {e}")

report_path = root / "memory" / "logs" / "fixer_report.json"
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(results, f, indent=2)

print(f"\n\n=== FIXER REPORT SAVED ===\n{report_path}\n")
fixed = sum(1 for r in results if r.get("status") == "fixed")
partial = sum(1 for r in results if r.get("status") == "partial")
needs_user = sum(1 for r in results if r.get("status") == "needs_user")
failed = sum(1 for r in results if r.get("status") == "failed")
ok = sum(1 for r in results if r.get("status") == "ok")
print(f"Fixed: {fixed} | Partial: {partial} | Needs user: {needs_user} | Failed: {failed} | OK: {ok}")
