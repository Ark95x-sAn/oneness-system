"""Aura controller: starts/stops all ambient subagents."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent.parent
SRC = ROOT / "src"
PYTHON = ROOT / "venv" / "Scripts" / "python.exe"
SUBAGENTS = [
    "aura.watcher",
    "aura.subagents.gameguard",
    "aura.subagents.idlecleaner",
    "aura.subagents.rambalancer",
    "aura.subagents.signalforge_lite",
    "aura.subagents.tradewatch",
    "aura.subagents.healthwealth",
    "aura.subagents.selfsaboteur_watch",
]
PID_FILE = ROOT / "memory" / "aura" / "subagent_pids.json"


def _env() -> dict[str, str]:
    env = os.environ.copy()
    pythonpath = env.get("PYTHONPATH", "")
    src_str = str(SRC)
    if src_str not in pythonpath.split(os.pathsep):
        env["PYTHONPATH"] = src_str + (os.pathsep + pythonpath if pythonpath else "")
    return env


def start_all() -> dict[str, Any]:
    import json
    procs = []
    env = _env()
    for module in SUBAGENTS:
        proc = subprocess.Popen(
            [str(PYTHON), "-m", module],
            cwd=str(ROOT),
            env=env,
            creationflags=subprocess.CREATE_NO_WINDOW,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        procs.append({"module": module, "pid": proc.pid})
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(json.dumps(procs, indent=2), encoding="utf-8")
    return {"started": len(procs), "processes": procs}


def stop_all() -> dict[str, Any]:
    import json, psutil
    killed = []
    if PID_FILE.exists():
        for entry in json.loads(PID_FILE.read_text(encoding="utf-8")):
            try:
                psutil.Process(entry["pid"]).kill()
                killed.append(entry)
            except Exception:
                pass
    for module in SUBAGENTS:
        name = module.split(".")[-1]
        for p in psutil.process_iter(["pid", "name", "cmdline"]):
            cmdline = " ".join(p.info.get("cmdline") or [])
            if name in cmdline.lower() or module in cmdline.lower():
                try:
                    p.kill()
                    killed.append({"pid": p.pid, "module": module})
                except Exception:
                    pass
    return {"stopped": len(killed), "processes": killed}


def status() -> dict[str, Any]:
    import json, psutil
    result = {"running": [], "missing": []}
    if PID_FILE.exists():
        for entry in json.loads(PID_FILE.read_text(encoding="utf-8")):
            try:
                p = psutil.Process(entry["pid"])
                result["running"].append({"module": entry["module"], "pid": entry["pid"], "status": p.status()})
            except Exception:
                result["missing"].append(entry)
    return result


def main():
    if len(sys.argv) < 2:
        print("Usage: controller.py {start|stop|status}")
        return
    cmd = sys.argv[1]
    if cmd == "start":
        print(start_all())
    elif cmd == "stop":
        print(stop_all())
    elif cmd == "status":
        print(status())
    else:
        print("Unknown command")


if __name__ == "__main__":
    main()
