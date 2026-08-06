
"""orchestrate.py — Oneness Sub-Agent Orchestrator.

Delegates PC automation tasks to specialized sub-agents, gathers raw
findings, stacks and compresses them, generates remediation scripts,
and optionally sends a summary alert.

This integrates with the main Oneness orchestrator (Synapse) and can be
run standalone or as a scheduled task.
"""
import argparse
import json
import logging
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Ensure src/ is on path when this script is run directly
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR.parent))

from subagents import (
    RAW_DIR, STACKED_DIR, COMPRESSED_DIR, REMEDIATIONS_DIR, LOG_DIR,
    ensure_dirs, now_iso,
)
from subagents.alert_ops import send

PYTHON = sys.executable

ensure_dirs()
LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / "subagent_orchestrate.log", encoding="utf-8", mode="a"),
    ],
)
log = logging.getLogger("subagents")

AGENTS = [
    ("cpu_ops", []),
    ("system_tech", []),
    ("cleanup_ops", []),
    ("file_ops", []),
    ("code_ops", []),
    ("browser_ops", []),
    ("notion_ops", []),
    ("web_research", []),
]

def run_agent(name: str, extra_args: list) -> dict:
    script = SCRIPT_DIR / f"{name}.py"
    if not script.exists():
        return {"agent": name, "status": "missing", "error": f"{script} not found"}
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out_path = RAW_DIR / f"{name}-{ts}.json"
    cmd = [PYTHON, str(script), "--out", str(out_path), *extra_args]
    log.info("Delegating to %s", name)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=180, check=False)
        if result.returncode != 0:
            log.warning("Agent %s exited %d: %s", name, result.returncode, result.stderr.strip())
            return {"agent": name, "status": "error", "stderr": result.stderr.strip()}
        lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
        data = json.loads(lines[-1]) if lines else {}
        data["agent"] = name
        data["status"] = data.get("status", "ok")
        data["out_path"] = str(out_path)
        return data
    except subprocess.TimeoutExpired:
        return {"agent": name, "status": "timeout"}
    except Exception as exc:
        return {"agent": name, "status": "exception", "error": str(exc)}

def stack_and_compress() -> Path:
    compressed_path = COMPRESSED_DIR / "latest-brief.json"
    cmd = [PYTHON, str(SCRIPT_DIR / "stack_compress.py"), "--raw-dir", str(RAW_DIR), "--out", str(compressed_path), "--top-n", "10"]
    log.info("Stacking and compressing sub-agent findings")
    subprocess.run(cmd, check=True, timeout=120)
    return compressed_path

def generate_remediations(brief_path: Path, risk_threshold: float = 0.6) -> list:
    cmd = [PYTHON, str(SCRIPT_DIR / "pc_remediate.py"), "--brief", str(brief_path), "--out-dir", str(REMEDIATIONS_DIR), "--risk-threshold", str(risk_threshold)]
    log.info("Generating remediation scripts")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, check=False)
    if result.returncode != 0:
        log.error("pc_remediate failed: %s", result.stderr.strip())
        return []
    data = json.loads(result.stdout.splitlines()[-1]) if result.stdout.strip() else {}
    return data.get("generated", [])

def send_summary(brief_path: Path, generated: list):
    try:
        brief = json.loads(brief_path.read_text(encoding="utf-8"))
        top = brief.get("top_findings", [])
        title = f"Oneness Sub-Agent Brief — {brief.get('total_findings', 0)} findings"
        msg = "\n".join([f"{i+1}. {f.get('type')} — {f.get('title')}" for i, f in enumerate(top[:5])])
        msg += f"\n\nGenerated {len(generated)} remediation script(s) for review."
        send(title, msg, channels=["toast"])
    except Exception as exc:
        log.warning("Summary alert failed: %s", exc)


# CPU pressure guard: skip heavy agents when system is saturated
def _active_agents():
    try:
        import psutil
        cpu = psutil.cpu_percent(interval=0.3)
        if cpu >= 90:
            log.warning("CPU pressure guard active: %s%% — still running bot team (cpu_ops, cleanup_ops, file_ops) plus system_tech", cpu)
            heavy = {"code_ops", "browser_ops", "notion_ops", "web_research"}
            return [a for a in AGENTS if a[0] not in heavy]
    except Exception:
        pass
    return AGENTS

def cycle(risk_threshold: float = 0.6, alert: bool = True) -> dict:
    log.info("=== SUB-AGENT CYCLE START ===")
    results = []
    for name, extra_args in _active_agents():
        results.append(run_agent(name, extra_args))
        time.sleep(0.2)

    brief_path = stack_and_compress()
    generated = generate_remediations(brief_path, risk_threshold)
    if alert:
        send_summary(brief_path, generated)

    meta = {
        "last_cycle": now_iso(),
        "agents": results,
        "brief": str(brief_path),
        "remediations": generated,
    }
    (SCRIPT_DIR / "state.json").write_text(json.dumps(meta, indent=2), encoding='utf-8')
    log.info("=== SUB-AGENT CYCLE COMPLETE ===")
    return meta

def health() -> dict:
    return {
        "raw_count": len(list(RAW_DIR.glob("*.json"))),
        "compressed_exists": (COMPRESSED_DIR / "latest-brief.json").exists(),
        "remediation_count": len(list(REMEDIATIONS_DIR.glob("*.ps1"))),
    }

def main():
    parser = argparse.ArgumentParser(description="Oneness Sub-Agent Orchestrator")
    parser.add_argument("--cycle", action="store_true", help="Run one full sub-agent cycle")
    parser.add_argument("--health", action="store_true", help="Show sub-agent health")
    parser.add_argument("--risk-threshold", type=float, default=0.6)
    parser.add_argument("--no-alert", action="store_true")
    args = parser.parse_args()

    if args.cycle:
        meta = cycle(args.risk_threshold, alert=not args.no_alert)
        print(json.dumps(meta, indent=2))
    elif args.health:
        print(json.dumps(health(), indent=2))
    else:
        parser.print_help()

if __name__ == "__main__":
    main()