#!/usr/bin/env python3
"""Oneness System deployment readiness health check."""
import sys
import subprocess
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = []

def check(name, cmd, expect_zero=True):
    try:
        result = subprocess.run(cmd, cwd=ROOT, shell=True, capture_output=True, text=True, timeout=30)
        ok = (result.returncode == 0) if expect_zero else (result.returncode != 0)
        RESULTS.append({"name": name, "ok": ok, "returncode": result.returncode, "stderr": result.stderr[:200]})
        print(f"{'[OK]' if ok else '[FAIL]'} {name}")
    except Exception as e:
        RESULTS.append({"name": name, "ok": False, "error": str(e)})
        print(f"[FAIL] {name}: {e}")

print("=== Oneness System Health Check ===\n")

check("Python syntax", f"{sys.executable} -m py_compile src/oneness_orchestrator.py")
check("Agent syntax", f"{sys.executable} -m py_compile src/agents/oraclevault.py")
check("Pytest", f"{sys.executable} -m pytest tests/ -q")
check("YAML config", f"{sys.executable} -c \"import yaml; yaml.safe_load(open('config/agents.yaml'))\"")
check("Docker daemon", "docker version")
check("Node available", "node --version")
check("npx available", "npx --version")

out_path = ROOT / "memory" / "logs" / "health_check.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(RESULTS, f, indent=2)

print(f"\nResults written to {out_path}")
all_ok = all(r["ok"] for r in RESULTS)
sys.exit(0 if all_ok else 1)
