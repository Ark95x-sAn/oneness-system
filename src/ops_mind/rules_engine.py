"""rules_engine.py — IFTTT-style automation rule engine for the Operations Mind.

Evaluates "if this then that" rules against the latest monitor snapshots and
findings. Each rule has:
  - trigger: what condition to check (from monitor data)
  - condition: comparison operator + threshold
  - action: what to do (alert, remediation, script, api_call, chain_rule)
  - cooldown: minimum seconds between firings (prevents spam)

Rules are loaded from memory/ops_mind/rules/*.json and evaluated on each cycle.
All destructive actions generate preview-only scripts — nothing auto-executes.
"""
import json
import os
import time
import subprocess
from pathlib import Path
from datetime import datetime, timezone

from . import OPS_MIND_ROOT, REMEDIATIONS_DIR, now_iso, write_json, load_json

RULES_DIR = OPS_MIND_ROOT / "rules"
LOG_DIR = OPS_MIND_ROOT / "logs"
FIRINGS_DIR = OPS_MIND_ROOT / "firings"

# Ensure dirs exist
for d in (RULES_DIR, FIRINGS_DIR):
    d.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Condition evaluators
# ---------------------------------------------------------------------------
OPERATORS = {
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
    ">": lambda a, b: float(a) > float(b),
    ">=": lambda a, b: float(a) >= float(b),
    "<": lambda a, b: float(a) < float(b),
    "<=": lambda a, b: float(a) <= float(b),
    "contains": lambda a, b: str(b) in str(a),
    "not_contains": lambda a, b: str(b) not in str(a),
    "starts_with": lambda a, b: str(a).startswith(str(b)),
    "ends_with": lambda a, b: str(a).endswith(str(b)),
    "in": lambda a, b: a in b,
    "not_in": lambda a, b: a not in b,
    "exists": lambda a, b: a is not None,
    "empty": lambda a, b: not a,
    "not_empty": lambda a, b: bool(a),
}


def resolve_value(path, data):
    """Resolve a dotted path like 'telemetry.cpu_percent' from nested dicts."""
    parts = path.split(".")
    current = data
    for part in parts:
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list):
            try:
                current = current[int(part)]
            except (ValueError, IndexError):
                return None
        else:
            return None
    return current


def evaluate_condition(trigger, condition, snapshots, findings):
    """Evaluate a single trigger/condition against monitor data.
    
    trigger format:
      {"source": "telemetry", "field": "cpu_percent"}  -> snapshots.telemetry.cpu_percent
      {"source": "findings", "field": "type", "match": "cpu_critical"}  -> any finding with type==match
      {"source": "findings_count", "field": "critical"}  -> count of critical findings
      {"source": "constant", "value": 90}  -> literal value
    """
    source = trigger.get("source", "snapshots")
    field = trigger.get("field", "")
    
    if source == "constant":
        return trigger.get("value")
    
    if source == "findings_count":
        severity = trigger.get("match", "critical")
        count = sum(1 for f in findings if f.get("severity") == severity)
        return count
    
    if source == "findings":
        match_val = trigger.get("match")
        if match_val:
            matched = [f for f in findings if resolve_value(field, f) == match_val]
            return len(matched) if matched else 0
        return [resolve_value(field, f) for f in findings]
    
    if source == "snapshots":
        return resolve_value(field, snapshots)
    
    # Direct lookup in snapshots
    return resolve_value(f"{source}.{field}", snapshots)


def check_rule(rule, snapshots, findings):
    """Check if a rule's trigger fires. Returns (fired: bool, actual_value)."""
    trigger = rule.get("trigger", {})
    condition = rule.get("condition", {})
    
    actual = evaluate_condition(trigger, condition, snapshots, findings)
    
    if actual is None:
        return False, None
    
    operator = condition.get("operator", ">=")
    threshold = condition.get("value")
    
    op_func = OPERATORS.get(operator)
    if not op_func:
        return False, None
    
    try:
        fired = op_func(actual, threshold)
        return fired, actual
    except (TypeError, ValueError):
        return False, None


# ---------------------------------------------------------------------------
# Action executors
# ---------------------------------------------------------------------------
def execute_action(action, rule, actual_value, snapshots, findings):
    """Execute the rule's action. All actions are SAFE (preview-only or informational)."""
    action_type = action.get("type", "alert")
    result = {"type": action_type, "rule_id": rule.get("id"), "timestamp": now_iso()}
    
    if action_type == "alert":
        msg = action.get("message", f"Rule {rule['id']} triggered: {actual_value}")
        msg = msg.replace("{actual}", str(actual_value))
        result["message"] = msg
        result["severity"] = action.get("severity", "warning")
    
    elif action_type == "remediation":
        msg = action.get("message", f"Rule {rule['id']} triggered: {actual_value}")
        msg = msg.replace("{actual}", str(actual_value))
        result["message"] = msg
        # Generate a preview-only remediation script
        script_name = f"{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}_{rule['id']}.ps1"
        script_path = REMEDIATIONS_DIR / script_name
        lines = [
            f"# IFTTT REMEDIATION: {rule.get('name', rule['id'])}",
            f"# Trigger: {rule.get('trigger', {})}",
            f"# Condition: {rule.get('condition', {})}",
            f"# Actual value: {actual_value}",
            f"# Generated: {now_iso()}",
            f"# REVIEW BEFORE RUNNING — this script is preview-only",
            "",
        ]
        lines.extend(action.get("script_lines", ["# No script lines defined"]))
        script_path.write_text("\r\n".join(lines), encoding="utf-8")
        result["script_path"] = str(script_path)
        result["message"] = f"Remediation script generated: {script_name}"
    
    elif action_type == "script":
        # Invoke a Python/PowerShell script (safe — just records the suggestion)
        cmd = action.get("command", "")
        result["command"] = cmd
        result["message"] = f"Script suggested: {cmd}"
        result["note"] = "Script not auto-executed. Run manually after review."
    
    elif action_type == "api_call":
        # Suggest an API endpoint to call
        endpoint = action.get("endpoint", "")
        method = action.get("method", "POST")
        result["endpoint"] = endpoint
        result["method"] = method
        result["message"] = f"API call suggested: {method} {endpoint}"
    
    elif action_type == "chain_rule":
        # Chain to another rule
        chain_id = action.get("rule_id", "")
        result["chain_rule_id"] = chain_id
        result["message"] = f"Chain to rule: {chain_id}"
    
    elif action_type == "log":
        msg = action.get("message", f"Rule {rule['id']} logged: {actual_value}")
        msg = msg.replace("{actual}", str(actual_value))
        result["message"] = msg
    
    return result


# ---------------------------------------------------------------------------
# Cooldown tracking
# ---------------------------------------------------------------------------
_last_fired = {}  # rule_id -> timestamp

def is_cooled_down(rule_id, cooldown_seconds):
    """Check if a rule has cooled down since last firing."""
    if rule_id not in _last_fired:
        return True
    elapsed = time.time() - _last_fired[rule_id]
    return elapsed >= cooldown_seconds


def mark_fired(rule_id):
    _last_fired[rule_id] = time.time()


# ---------------------------------------------------------------------------
# Main rule evaluation
# ---------------------------------------------------------------------------
def load_rules():
    """Load all rules from the rules directory."""
    rules = []
    if not RULES_DIR.exists():
        return rules
    
    for rule_file in sorted(RULES_DIR.glob("*.json")):
        try:
            data = json.loads(rule_file.read_text(encoding="utf-8"))
            if isinstance(data, list):
                rules.extend(data)
            elif isinstance(data, dict):
                if "rules" in data:
                    rules.extend(data["rules"])
                else:
                    rules.append(data)
        except Exception as exc:
            rules.append({"id": "load_error", "error": str(exc), "file": str(rule_file)})
    
    return rules


def evaluate_all_rules(snapshots, findings):
    """Evaluate all loaded rules against the current monitor data.
    
    Returns list of firing results.
    """
    rules = load_rules()
    firings = []
    
    for rule in rules:
        rule_id = rule.get("id", "unknown")
        if rule.get("error"):
            firings.append({
                "rule_id": rule_id,
                "fired": False,
                "error": rule["error"],
                "timestamp": now_iso(),
            })
            continue
        
        if not rule.get("enabled", True):
            continue
        
        # Check cooldown
        cooldown = rule.get("cooldown_seconds", 300)
        if not is_cooled_down(rule_id, cooldown):
            continue
        
        # Evaluate the trigger
        fired, actual = check_rule(rule, snapshots, findings)
        
        if fired:
            mark_fired(rule_id)
            
            # Execute the action
            action = rule.get("action", {"type": "alert", "message": f"{rule_id} triggered"})
            result = execute_action(action, rule, actual, snapshots, findings)
            result["fired"] = True
            result["actual_value"] = actual
            result["rule_name"] = rule.get("name", rule_id)
            result["trigger"] = rule.get("trigger", {})
            result["condition"] = rule.get("condition", {})
            
            firings.append(result)
    
    # Save firings
    if firings:
        firing_path = FIRINGS_DIR / f"firings-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
        write_json(firing_path, firings)
        
        # Update latest
        write_json(FIRINGS_DIR / "latest-firings.json", {
            "generated_at": now_iso(),
            "total_firings": len(firings),
            "firings": firings,
        })
    
    return firings


def get_rules_summary():
    """Return a summary of all loaded rules and their status."""
    rules = load_rules()
    summary = []
    for rule in rules:
        summary.append({
            "id": rule.get("id", "unknown"),
            "name": rule.get("name", ""),
            "enabled": rule.get("enabled", True),
            "trigger": rule.get("trigger", {}),
            "condition": rule.get("condition", {}),
            "action_type": rule.get("action", {}).get("type", "alert"),
            "cooldown_seconds": rule.get("cooldown_seconds", 300),
            "last_fired": datetime.fromtimestamp(_last_fired[rule.get("id", "")], timezone.utc).isoformat() if rule.get("id") in _last_fired else None,
        })
    return summary