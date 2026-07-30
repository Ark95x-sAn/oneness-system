"""
Prime Fire Council Meta-Agent (2045 edition)
Self-healing loop for the Oneness System.
Run from Task Scheduler or manually:
    python src/meta_agent.py
"""
import json
import subprocess
import time
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent
PRIME = ROOT / "venv" / "Scripts" / "prime.exe"
LOG = ROOT / "memory" / "logs" / "meta_agent.log"

def log(msg):
    line = f"{datetime.now().isoformat()} | {msg}"
    print(line)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def run_prime(*args):
    cmd = [str(PRIME), "--json"] + list(args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=ROOT)
        return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {"ok": False, "stderr": r.stderr}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def main():
    log("Meta-agent cycle started")
    doctor = run_prime("doctor")
    if not doctor.get("ready"):
        log("System not ready; attempting start")
        run_prime("start")
        time.sleep(5)
        doctor = run_prime("doctor")
    log(f"Doctor ready={doctor.get('ready')}")

    status = run_prime("status")
    if not status.get("web_ok"):
        log("Web API not ok; running fixers")
        run_prime("fix")
    else:
        log(f"Status ok; agents={len(status.get('agents', []))}")

    # Tick any unhealthy agents
    for agent in status.get("agents", []):
        if not agent.get("healthy", True):
            aid = agent.get("id")
            log(f"Ticking unhealthy agent {aid}")
            run_prime("agents", "tick", aid)

    log("Meta-agent cycle complete")

if __name__ == "__main__":
    main()
