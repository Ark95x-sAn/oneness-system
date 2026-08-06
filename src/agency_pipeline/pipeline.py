"""
agency_pipeline.py — Multi-layer agent automation pipeline.

One chat instruction enters the Agency Layer, which:
  1. Parses intent and scope.
  2. Selects a workflow blueprint.
  3. Delegates to layer-1 coordinators (OnenessOrchestrator, SovereignDesktop, SubAgentCrew, Net95X, CometX9).
  4. Each coordinator fans out to layer-2 worker agents / sub-agents.
  5. Results stack, compress, and flow back to the dashboard/intent log.

No autopilot. Destructive actions require explicit confirmation.
"""
import json
import datetime
import subprocess
from pathlib import Path
from typing import List, Dict, Any

ROOT = Path(__file__).resolve().parent.parent.parent
SRC = ROOT / "src"
MEMORY = ROOT / "memory" / "agency"
PIPELINE_DIR = MEMORY / "pipelines"
PIPELINE_DIR.mkdir(parents=True, exist_ok=True)


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Workflow blueprints
# ---------------------------------------------------------------------------
BLUEPRINTS = {
    "storage_cleanup": {
        "display": "Storage Cleanup & Compression",
        "description": "Scan raw memory dirs, compress/dedupe, archive old raw files, refresh dashboard.",
        "layers": [
            {"layer": 1, "coordinator": "sovereign_desktop", "task": "scan_system"},
            {"layer": 2, "coordinator": "subagents", "agents": ["cleanup_ops", "file_ops", "cpu_ops"]},
            {"layer": 3, "coordinator": "stack_compress", "target_dirs": ["memory/subagents/raw"]},
            {"layer": 4, "coordinator": "storage_compress", "target_dirs": ["memory/subagents/raw", "memory/net95x/raw"]},
            {"layer": 5, "coordinator": "sovereign_desktop", "task": "refresh_dashboard"},
        ]
    },
    "legal_intelligence": {
        "display": "Legal Intelligence Sweep",
        "description": "Search local files, browser histories, and web for case-related intelligence.",
        "layers": [
            {"layer": 1, "coordinator": "sovereign_desktop", "task": "scan_apps", "apps": ["chatgpt_desktop", "claude_code", "chrome", "edge"]},
            {"layer": 2, "coordinator": "subagents", "agents": ["file_ops", "browser_ops", "web_research"], "keywords": ["RSB", "Nordskog", "EQCV018537", "foreclosure"]},
            {"layer": 3, "coordinator": "stack_compress", "target_dirs": ["memory/subagents/raw"]},
            {"layer": 4, "coordinator": "sovereign_desktop", "task": "open_dashboard", "dashboard": "cases/rsb_nordskog/legal_commander.html"},
        ]
    },
    "wealth_engine": {
        "display": "Passive Wealth Engine Run",
        "description": "Run income-play ranking and top-opportunity scouting.",
        "layers": [
            {"layer": 1, "coordinator": "sovereign_desktop", "task": "scan_apps", "apps": ["codex_cli", "openclaw"]},
            {"layer": 2, "coordinator": "comet_x9", "task": "income_ops"},
            {"layer": 3, "coordinator": "stack_compress", "target_dirs": ["memory/comet_x9/raw"]},
            {"layer": 4, "coordinator": "sovereign_desktop", "task": "open_dashboard", "dashboard": "comet_commander.html"},
        ]
    },
    "system_health": {
        "display": "System Health & Remediation",
        "description": "Run PC health sub-agents and generate remediations for review.",
        "layers": [
            {"layer": 1, "coordinator": "subagents", "agents": ["cpu_ops", "system_tech", "cleanup_ops", "pc_remediate"]},
            {"layer": 2, "coordinator": "stack_compress", "target_dirs": ["memory/subagents/raw"]},
            {"layer": 3, "coordinator": "sovereign_desktop", "task": "refresh_dashboard"},
        ]
    },
    "custom": {
        "display": "Custom Agency Instruction",
        "description": "Pass user text directly to available coordinators and log intent.",
        "layers": [
            {"layer": 1, "coordinator": "sovereign_desktop", "task": "log_intent"},
            {"layer": 2, "coordinator": "subagents", "agents": ["file_ops", "browser_ops", "web_research", "code_ops"]},
            {"layer": 3, "coordinator": "stack_compress", "target_dirs": ["memory/subagents/raw"]},
        ]
    }
}


def list_blueprints() -> Dict[str, Any]:
    return {k: {"display": v["display"], "description": v["description"]} for k, v in BLUEPRINTS.items()}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _last_json_block(stdout: str) -> Any:
    """Extract the last JSON object/array block from mixed stdout output."""
    if not stdout or not stdout.strip():
        return {}
    lines = stdout.splitlines()
    for i in range(len(lines) - 1, -1, -1):
        stripped = lines[i].strip()
        if stripped.startswith("{") or stripped.startswith("["):
            block = "\n".join(lines[i:])
            try:
                return json.loads(block)
            except Exception:
                continue
    return {}


# ---------------------------------------------------------------------------
# Layer dispatchers
# ---------------------------------------------------------------------------
def run_subagent_cycle(agents: List[str] = None, keywords: List[str] = None) -> Dict[str, Any]:
    cmd = ["python", str(SRC / "subagents" / "orchestrate.py"), "--cycle", "--no-alert"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False)
        if result.returncode != 0:
            return {"ok": False, "stderr": result.stderr.strip()[:500]}
        data = _last_json_block(result.stdout)
        data["ok"] = True
        return data
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def run_stack_compress(target_dirs: List[str]) -> Dict[str, Any]:
    findings = []
    raw_count = 0
    for rel in target_dirs:
        raw_dir = ROOT / rel
        if not raw_dir.exists():
            continue
        out_path = raw_dir.parent / "compressed" / "latest-brief.json"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            result = subprocess.run(
                ["python", str(SRC / "subagents" / "stack_compress.py"), "--raw-dir", str(raw_dir), "--out", str(out_path), "--top-n", "20"],
                capture_output=True, text=True, timeout=300, check=False
            )
            if result.returncode == 0:
                data = _last_json_block(result.stdout)
                findings.append({"dir": rel, "out": str(out_path), "total": data.get("total", 0)})
                raw_count += data.get("raw_files_scanned", 0)
            else:
                findings.append({"dir": rel, "error": result.stderr.strip()[:500]})
        except Exception as exc:
            findings.append({"dir": rel, "error": str(exc)})
    return {"ok": True, "findings": findings, "raw_files_scanned": raw_count}


def run_storage_compress(target_dirs: List[str]) -> Dict[str, Any]:
    try:
        result = subprocess.run(
            ["python", str(SRC / "agency_pipeline" / "workers" / "storage_compressor.py"), "--target-dirs", *target_dirs, "--confirmed"],
            capture_output=True, text=True, timeout=300, check=False
        )
        if result.returncode != 0:
            return {"ok": False, "stderr": result.stderr.strip()[:500]}
        return _last_json_block(result.stdout)
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def run_sovereign_desktop(task: str, **kwargs) -> Dict[str, Any]:
    if task == "scan_system":
        try:
            result = subprocess.run(["python", str(ROOT / "scan_sovereign.py")], capture_output=True, text=True, timeout=60, check=False)
            return {"ok": result.returncode == 0, "output": result.stdout.strip()[:1000]}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}
    if task == "refresh_dashboard":
        try:
            result = subprocess.run(["python", str(SRC / "sovereign_desktop" / "refresh_dashboard.py")], capture_output=True, text=True, timeout=60, check=False)
            return {"ok": result.returncode == 0, "output": result.stdout.strip()[:500]}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}
    if task == "log_intent":
        return {"ok": True, "note": "Intent logged; no auto-execution."}
    return {"ok": False, "error": f"unknown sovereign_desktop task: {task}"}


def run_comet_x9(task: str) -> Dict[str, Any]:
    return {"ok": True, "note": f"CometX9 task '{task}' dispatched (stub)."}


def dispatch_layer(step: Dict[str, Any]) -> Dict[str, Any]:
    coord = step.get("coordinator")
    if coord == "subagents":
        return run_subagent_cycle(step.get("agents"), step.get("keywords"))
    if coord == "stack_compress":
        return run_stack_compress(step.get("target_dirs", []))
    if coord == "storage_compress":
        return run_storage_compress(step.get("target_dirs", []))
    if coord == "sovereign_desktop":
        return run_sovereign_desktop(step.get("task"), **{k: v for k, v in step.items() if k not in ("coordinator", "task", "layer")})
    if coord == "comet_x9":
        return run_comet_x9(step.get("task"))
    return {"ok": False, "error": f"unknown coordinator: {coord}"}


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------
def run_pipeline(blueprint_key: str, user_text: str = "", confirmed: bool = False) -> Dict[str, Any]:
    if not confirmed:
        return {
            "ok": False,
            "status": "preview",
            "blueprint": blueprint_key,
            "display": BLUEPRINTS.get(blueprint_key, {}).get("display", blueprint_key),
            "message": f"Confirm before running agency pipeline '{blueprint_key}'. Reply 'yes' or set confirmed=True.",
            "steps": BLUEPRINTS.get(blueprint_key, {}).get("layers", [])
        }

    blueprint = BLUEPRINTS.get(blueprint_key, BLUEPRINTS["custom"])
    started = now_iso()
    results = []
    for step in blueprint["layers"]:
        results.append({"step": step, "result": dispatch_layer(step), "timestamp": now_iso()})

    record = {
        "id": f"{blueprint_key}-{datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')}",
        "blueprint": blueprint_key,
        "user_text": user_text,
        "started": started,
        "completed": now_iso(),
        "results": results,
        "status": "completed"
    }
    path = PIPELINE_DIR / f"{record['id']}.json"
    path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    return {"ok": True, "record": record, "path": str(path)}


def parse_instruction(text: str) -> str:
    t = text.lower()
    if any(w in t for w in ["storage", "cleanup", "compress", "free space", "organize files"]):
        return "storage_cleanup"
    if any(w in t for w in ["legal", "rsb", "nordskog", "foreclosure", "case"]):
        return "legal_intelligence"
    if any(w in t for w in ["wealth", "income", "money", "passive", "comet"]):
        return "wealth_engine"
    if any(w in t for w in ["health", "remediation", "system", "pc fix"]):
        return "system_health"
    return "custom"


def handle_chat_instruction(text: str, confirmed: bool = False) -> Dict[str, Any]:
    blueprint = parse_instruction(text)
    return run_pipeline(blueprint, user_text=text, confirmed=confirmed)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--blueprint", default="custom")
    parser.add_argument("--text", default="")
    parser.add_argument("--confirmed", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list:
        print(json.dumps(list_blueprints(), indent=2))
    else:
        print(json.dumps(handle_chat_instruction(args.text or args.blueprint, confirmed=args.confirmed), indent=2))
