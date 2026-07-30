"""Pattern Signature Engine - computes the user's operational hash/avatar from system telemetry."""
from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", r"C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem"))
MEMORY = ROOT / "memory"
SIG_DIR = MEMORY / "signatures"
SIG_DIR.mkdir(parents=True, exist_ok=True)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None


def _hash_blob(*parts: bytes) -> str:
    h = hashlib.sha3_256()
    for p in parts:
        h.update(p)
    return h.hexdigest()[:32]


def _frequency_score() -> dict[str, float]:
    aura = _read_json(MEMORY / "aura" / "latest.json") or {}
    gaming = aura.get("is_gaming", False)
    load = aura.get("cpu_percent", 0)
    if gaming:
        return {"band": 1111, "label": "Foundation/Flow", "strength": 0.95}
    if load > 70:
        return {"band": 852, "label": "System AI resonance", "strength": 0.85}
    return {"band": 3333, "label": "Mastery/Build", "strength": 0.9}


def _gate_progress() -> dict[str, Any]:
    gates_list = _read_json(MEMORY / "progression" / "gates.json") or []
    if not gates_list:
        return {"current_gate": 1, "cleared": 0}
    cleared = sum(1 for g in gates_list if g.get("cleared"))
    current = next((g for g in gates_list if g.get("unlocked") and not g.get("cleared")), gates_list[0] if gates_list else {})
    return {"current_gate": current.get("number", 1), "cleared": cleared, "boss": current.get("boss", {}).get("name")}


def _file_entropy(paths: list[Path]) -> float:
    sizes = []
    for p in paths:
        try:
            sizes.append(p.stat().st_size)
        except Exception:
            pass
    if not sizes:
        return 0.0
    avg = sum(sizes) / len(sizes)
    variance = sum((s - avg) ** 2 for s in sizes) / len(sizes)
    return round(variance ** 0.5 / (avg + 1), 4)


def compute_signature() -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    aura = _read_json(MEMORY / "aura" / "latest.json") or {}
    risk = _read_json(MEMORY / "risk_state.json") or {}
    audit = _read_json(MEMORY / "logs" / "audit_trail.json") or []
    recent_audit = audit[-20:] if isinstance(audit, list) else []

    project_files = [
        ROOT / "memory" / "legal" / "cases" / "EQCV018537" / "narrative.md",
        ROOT / "memory" / "polymarket" / "lite_signals.json",
        ROOT / "memory" / "vault" / "1-Projects" / "Net95xApp" / "net95x.html",
    ]
    project_hashes = {str(p.name): _hash_blob(p.read_bytes()) for p in project_files if p.exists()}

    freq = _frequency_score()
    gates = _gate_progress()

    identity_seed = json.dumps({
        "user": os.environ.get("USERNAME", "ArcXN"),
        "frequency": freq,
        "gates": gates,
        "projects": sorted(project_hashes.items()),
        "aura_keys": sorted(aura.keys()),
    }, sort_keys=True).encode()
    signature_hash = _hash_blob(identity_seed, now.encode())

    glyph = ""
    for i, ch in enumerate(signature_hash[:16]):
        if i % 4 == 0:
            glyph += "  "
        glyph += "◉" if int(ch, 16) % 2 else "◎"
        if i % 4 == 3:
            glyph += "\n"

    signature = {
        "timestamp": now,
        "hash": signature_hash,
        "glyph": glyph.strip(),
        "frequency": freq,
        "gates": gates,
        "aura": {k: aura.get(k) for k in ("is_gaming", "cpu_percent", "memory_percent", "recommended_mode") if k in aura},
        "risk": risk,
        "projects": project_hashes,
        "recent_events": len(recent_audit),
        "entropy": _file_entropy(project_files),
        "version": "2045.1.0",
    }

    out_path = SIG_DIR / "latest_signature.json"
    out_path.write_text(json.dumps(signature, indent=2), encoding="utf-8")
    return signature


def predict_next_state(signature: dict[str, Any] | None = None) -> dict[str, Any]:
    sig = signature or compute_signature()
    gate = sig["gates"]["current_gate"]
    freq = sig["frequency"]["band"]
    events = sig["recent_events"]

    if gate == 1:
        next_action = "defeat Saboteur of Incompletion: admin install + Codex restart + .env keys"
        eta_gate_clear = "within 10 minutes of user action"
    elif gate == 2:
        next_action = "stabilize aura automation; launch paper trading bots"
        eta_gate_clear = "24-48 hours of runtime"
    elif gate == 3:
        next_action = "validate Polymarket edge; deploy capital with Kelly/EV limits"
        eta_gate_clear = "after 100+ paper trades with positive EV"
    else:
        next_action = "compound and scale"
        eta_gate_clear = "continuous"

    if freq < 2000:
        trajectory = "ascending from system resonance toward mastery"
    elif freq < 4000:
        trajectory = "mastery/build phase; optimal for heavy construction"
    else:
        trajectory = "high-frequency output phase; monitor for burnout"

    prediction = {
        "based_on_signature": sig["hash"],
        "next_action": next_action,
        "eta_gate_clear": eta_gate_clear,
        "trajectory": trajectory,
        "recommended_mode": sig["aura"].get("recommended_mode", "balanced"),
        "synthetic_confidence": round(min(0.99, 0.5 + events * 0.01), 2),
    }

    pred_path = SIG_DIR / "latest_prediction.json"
    pred_path.write_text(json.dumps(prediction, indent=2), encoding="utf-8")
    return prediction


if __name__ == "__main__":
    sig = compute_signature()
    pred = predict_next_state(sig)
    print(json.dumps({"signature": sig, "prediction": pred}, indent=2, default=str))
