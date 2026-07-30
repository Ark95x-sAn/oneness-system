"""Gate and Boss progression system for wealth, health, and operational mastery."""
from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .sigil import MEMORY_DIR

ROOT = Path(__file__).resolve().parent.parent.parent
CONFIG_YAML = ROOT / "config" / "agents.yaml"


@dataclass
class Boss:
    name: str
    gate: int
    pattern: str
    detection: dict[str, Any]
    defeat_action: str
    reward: str


@dataclass
class Gate:
    number: int
    name: str
    requirement: str
    boss: Boss
    unlocked: bool
    cleared: bool
    timestamp: str | None


GATES: list[Gate] = [
    Gate(
        number=1,
        name="Foundation",
        requirement="Oneness System installed and `prime doctor` returns ready",
        boss=Boss(
            name="The Saboteur of Incompletion",
            gate=1,
            pattern="leaving admin installers unrun, not restarting Codex, not filling .env",
            detection={"checks": ["admin_service_installed", "codex_restarted", "env_filled"]},
            defeat_action="Run Oneness Admin Install as admin; restart Codex; fill .env keys",
            reward="Windows service live; node_repl/Chrome control enabled; APIs authenticated",
        ),
        unlocked=True,
        cleared=False,
        timestamp=None,
    ),
    Gate(
        number=2,
        name="Automation",
        requirement="Aura subagents running and adapting to your sessions",
        boss=Boss(
            name="The Distraction Hydra",
            gate=2,
            pattern="many apps competing for RAM/CPU while gaming or working",
            detection={"checks": ["aura_subagents_running", "focus_mode_respected"]},
            defeat_action="Run `prime aura start`; let GameGuard pause cleaners during CoD; trim only when idle",
            reward="Gaming-aware optimization; background finance scans continue quietly",
        ),
        unlocked=False,
        cleared=False,
        timestamp=None,
    ),
    Gate(
        number=3,
        name="Capital",
        requirement="Live Polymarket data flowing and compound math validated",
        boss=Boss(
            name="The Risk Phantom",
            gate=3,
            pattern="trading without size limits, EV checks, or Kelly sizing",
            detection={"checks": ["polymarket_api_reachable", "risk_limits_configured"]},
            defeat_action="Set max order/exposure in config/agents.yaml; run `prime finance markets` daily; size via Kelly/EV",
            reward="Evidence-based prediction-market edge with bounded downside",
        ),
        unlocked=False,
        cleared=False,
        timestamp=None,
    ),
    Gate(
        number=4,
        name="Sovereignty",
        requirement="System self-heals, backs up memory, and survives reboots",
        boss=Boss(
            name="The Decay Warden",
            gate=4,
            pattern="logs pile up, configs drift, services fail silently over time",
            detection={"checks": ["daily_cleanup_active", "meta_agent_healthy", "service_auto_start"]},
            defeat_action="Confirm scheduled tasks `Oneness-*`; add cloud backup of memory/; run `prime fix` weekly",
            reward="24/7 durable organism that compounds data, capital, and capability",
        ),
        unlocked=False,
        cleared=False,
        timestamp=None,
    ),
    Gate(
        number=5,
        name="Ascension",
        requirement="Human-AI council operates with delegated authority and audit trail",
        boss=Boss(
            name="The Ego Sovereign",
            gate=5,
            pattern="refusing to delegate; micromanaging; ignoring the council",
            detection={"checks": ["delegation_log_present", "decision_audit_trail"]},
            defeat_action="Let SYNAPSE dispatch; review daily brief; approve or veto, never stall",
            reward="Maximum leverage: time, capital, intelligence, and freedom compound together",
        ),
        unlocked=False,
        cleared=False,
        timestamp=None,
    ),
]


def evaluate_gates() -> list[dict[str, Any]]:
    """Evaluate each gate and mark unlock/clear state based on current system checks."""
    results = []
    previous_cleared = True
    for gate in GATES:
        gate.unlocked = previous_cleared
        if gate.unlocked:
            gate.cleared = _check_gate(gate)
            if gate.cleared and gate.timestamp is None:
                gate.timestamp = datetime.now(timezone.utc).isoformat()
        results.append(asdict(gate))
        previous_cleared = previous_cleared and gate.cleared
    _save_gates(results)
    return results


def _check_gate(gate: Gate) -> bool:
    try:
        import psutil
    except ImportError:
        psutil = None
    checks = gate.boss.detection.get("checks", [])
    score = 0
    for check in checks:
        if check == "admin_service_installed":
            try:
                s = psutil.win_service_get("OnenessWeb")
                if s.status() == "running":
                    score += 1
            except Exception:
                pass
        elif check == "env_filled":
            env_file = ROOT / ".env"
            if env_file.exists() and "your-" not in env_file.read_text(encoding="utf-8"):
                score += 1
        elif check == "codex_restarted":
            try:
                import urllib.request
                urllib.request.urlopen("http://localhost:5050/api/health", timeout=2)
                score += 1
            except Exception:
                pass
        elif check == "aura_subagents_running":
            pid_file = ROOT / "memory" / "aura" / "subagent_pids.json"
            if pid_file.exists():
                score += 1
        elif check == "polymarket_api_reachable":
            try:
                import urllib.request
                req = urllib.request.Request("https://gamma-api.polymarket.com/markets?limit=1", headers={"User-Agent": "Oneness-Prime/2045"})
                urllib.request.urlopen(req, timeout=5)
                score += 1
            except Exception:
                pass
        elif check == "risk_limits_configured":
            if CONFIG_YAML.exists() and "max_order_size_usd" in CONFIG_YAML.read_text(encoding="utf-8"):
                score += 1
        elif check == "daily_cleanup_active":
            if (ROOT / "scripts" / "daily_cleanup.py").exists():
                score += 1
        elif check == "meta_agent_healthy":
            if (ROOT / "memory" / "logs" / "meta_agent.log").exists():
                score += 1
        else:
            score += 1
    return score >= max(1, len(checks) // 2)


def _save_gates(results: list[dict[str, Any]]) -> Path:
    import json
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / "gates.json"
    path.write_text(json.dumps(results, indent=2, default=str), encoding="utf-8")
    return path


def load_gates() -> list[dict[str, Any]]:
    import json
    path = MEMORY_DIR / "gates.json"
    if not path.exists():
        return evaluate_gates()
    return json.loads(path.read_text(encoding="utf-8"))


def current_boss() -> dict[str, Any] | None:
    import hashlib
    gates = evaluate_gates()
    for g in gates:
        if g["unlocked"] and not g["cleared"]:
            sigil = hashlib.sha256(f"{g['number']}:{g['boss']['name']}:852".encode()).hexdigest()[:16]
            return {
                "gate": g["number"],
                "gate_name": g["name"],
                "boss": g["boss"],
                "action": g["boss"]["defeat_action"],
                "reward": g["boss"]["reward"],
                "sigil": sigil,
            }
    return None
