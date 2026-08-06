"""orchestrate.py — Comet X9 Sovereign Core master controller.

Dispatches parallel sub-agents, stacks findings, generates preview-only
remediation scripts, and writes a unified status report.
"""
import argparse
import json
import logging
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR.parent))

from comet_x9 import RAW_DIR, COMPRESSED_DIR, REMEDIATIONS_DIR, LOG_DIR, ensure_dirs, now_iso

ensure_dirs()
LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / "comet_x9_orchestrate.log", encoding="utf-8", mode="a"),
    ],
)
log = logging.getLogger("comet_x9")

AGENTS = [
    ("admin_ops", []),
    ("network_ops", []),
    ("process_ops", []),
    ("app_launcher", []),
    ("telemetry_ops", []),
    ("income_ops", []),
    ("black_rock", []),
]

def run_agent(name, extra_args):
    script = SCRIPT_DIR / f"{name}.py"
    if not script.exists():
        return {"agent": name, "status": "missing", "error": f"{script} not found"}
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out_path = RAW_DIR / f"{name}-{ts}.json"
    cmd = [sys.executable, str(script), "--out", str(out_path), *extra_args]
    log.info("Delegating to %s", name)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, check=False)
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

def stack_and_compress():
    compressed_path = COMPRESSED_DIR / "latest-brief.json"
    cmd = [sys.executable, str(Path(__file__).resolve().parents[1] / "subagents" / "stack_compress.py"), "--raw-dir", str(RAW_DIR), "--out", str(compressed_path), "--top-n", "15"]
    log.info("Stacking Comet X9 findings")
    subprocess.run(cmd, check=True, timeout=120)
    return compressed_path

def generate_remediations(brief_path, risk_threshold=0.5):
    cmd = [sys.executable, str(Path(__file__).resolve().parents[1] / "subagents" / "pc_remediate.py"), "--brief", str(brief_path), "--out-dir", str(REMEDIATIONS_DIR), "--risk-threshold", str(risk_threshold)]
    log.info("Generating Comet X9 remediation scripts")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, check=False)
    if result.returncode != 0:
        log.error("pc_remediate failed: %s", result.stderr.strip())
        return []
    data = json.loads(result.stdout.splitlines()[-1]) if result.stdout.strip() else {}
    return data.get("generated", [])

def cycle(risk_threshold=0.5):
    log.info("=== COMET X9 SOVEREIGN CORE CYCLE START ===")
    results = []
    for name, extra_args in AGENTS:
        results.append(run_agent(name, extra_args))
        time.sleep(0.1)

    brief_path = stack_and_compress()
    generated = generate_remediations(brief_path, risk_threshold)

    meta = {
        "last_cycle": now_iso(),
        "agents": results,
        "brief": str(brief_path),
        "remediations": generated,
    }
    (SCRIPT_DIR / "state.json").write_text(json.dumps(meta, indent=2), encoding='utf-8')
    log.info("=== COMET X9 SOVEREIGN CORE CYCLE COMPLETE ===")
    return meta

def health():
    return {
        "raw_count": len(list(RAW_DIR.glob("*.json"))),
        "compressed_exists": (COMPRESSED_DIR / "latest-brief.json").exists(),
        "remediation_count": len(list(REMEDIATIONS_DIR.glob("*.ps1"))),
    }

def main():
    parser = argparse.ArgumentParser(description="Comet X9 Sovereign Core Orchestrator")
    parser.add_argument("--cycle", action="store_true")
    parser.add_argument("--health", action="store_true")
    parser.add_argument("--risk-threshold", type=float, default=0.5)
    args = parser.parse_args()

    if args.cycle:
        meta = cycle(args.risk_threshold)
        print(json.dumps(meta, indent=2))
    elif args.health:
        print(json.dumps(health(), indent=2))
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
