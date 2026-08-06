"""Sovereign Desktop Orchestrator: scan and launch apps safely."""
import json
import subprocess
import pathlib
from . import connectors
from .safety import preview, log, is_confirmed

REGISTRY = pathlib.Path(__file__).parent / "registry.json"


def load_registry():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def _running_patterns():
    registry = load_registry()
    patterns = [cfg.get("process_pattern", "") for cfg in registry["apps"].values() if cfg.get("process_pattern")]
    if not patterns:
        return []
    pat = "|".join(patterns)
    cmd = f"Get-Process | Where-Object {{ $_.ProcessName -match '{pat}' }} | Select-Object ProcessName | ConvertTo-Json -Compress"
    try:
        out = subprocess.check_output(["powershell", "-NoProfile", "-Command", cmd],
                                        stderr=subprocess.DEVNULL, timeout=10)
        data = json.loads(out)
        if isinstance(data, dict):
            data = [data]
        return data or []
    except Exception:
        return []


def scan():
    registry = load_registry()
    patterns = _running_patterns()
    results = []
    for app_id, cfg in registry["apps"].items():
        conn = connectors.GenericConnector(app_id, cfg)
        results.append(conn.status(patterns))
    return results


def launch(app_id: str, confirmed: bool = False):
    registry = load_registry()
    cfg = registry["apps"].get(app_id)
    if not cfg:
        return {"ok": False, "error": "unknown app"}
    if not confirmed and not is_confirmed("launch", app_id):
        return preview("launch", app_id, {
            "launch_type": cfg.get("launch_type"),
            "launch_value": cfg.get("launch_value")
        })
    conn = connectors.GenericConnector(app_id, cfg)
    result = conn.launch(confirmed=True)
    log("launch", app_id, True, result)
    return result
