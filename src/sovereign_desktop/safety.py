"""Safety gate: no autopilot, every action previewed and logged."""
import json
import datetime
import pathlib

LOG_PATH = pathlib.Path(__file__).parent / "action_log.json"
PRE_APPROVED = set()


def preview(action: str, target: str, params: dict = None):
    return {
        "approved": False,
        "action": action,
        "target": target,
        "params": params,
        "message": f"Confirm before running {action} on {target}."
    }


def confirm(action: str, target: str):
    PRE_APPROVED.add((action, target))
    return {"approved": True, "action": action, "target": target}


def is_confirmed(action: str, target: str):
    return (action, target) in PRE_APPROVED


def log(action: str, target: str, approved: bool, result: dict):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "action": action,
        "target": target,
        "approved": approved,
        "result": result
    }
    try:
        data = json.loads(LOG_PATH.read_text(encoding="utf-8")) if LOG_PATH.exists() else []
    except Exception:
        data = []
    data.append(entry)
    LOG_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
