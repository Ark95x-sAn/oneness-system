"""Detect user presence, activity, and gaming state from Windows signals."""
from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MEMORY_DIR = Path(__file__).resolve().parent.parent.parent / "memory" / "aura"


@dataclass
class AuraState:
    timestamp: str
    is_gaming: bool
    active_window_title: str
    active_process: str
    cpu_percent: float
    memory_available_mb: float
    mouse_idle_seconds: int
    keyboard_idle_seconds: int
    user_present: bool
    recommended_mode: str


def _normalize(text: str) -> str:
    # Strip zero-width and invisible unicode that games inject into window titles
    invisible = set(chr(c) for c in range(0x200B, 0x2010))  # zero-width chars
    invisible.update({"\x00", "\x7f", "\ufeff"})
    return "".join(c for c in text if c not in invisible).lower()


def detect_gaming(active_window: str, active_process: str, running_processes: set[str]) -> bool:
    # Strong signals: actual game processes or titles containing game names
    strong_terms = {"cod", "call of duty", "warzone", "modern warfare", "black ops", "battlefield", "apex legends", "fortnite", "valorant", "cs2", "league of legends", "rocket league", "gta", "rdr2", "elden ring"}
    text = _normalize(f"{active_window} {active_process}")
    if any(term in text for term in strong_terms):
        return True
    # Process-based detection: known game executables
    game_procs = {"cod.exe", "modernwarfare.exe", "warzone.exe", "blackops.exe", "apex.exe", "fortnite.exe", "valorant.exe", "cs2.exe"}
    if any(gp in running_processes for gp in game_procs):
        return True
    # Weak signals only count if an actual game-related process is running (not widgets/launchers)
    weak_terms = {"gaming", "game bar", "xbox game bar"}
    if any(term in text for term in weak_terms):
        return any(gp in running_processes for gp in game_procs)
    return False


def recommend_mode(state: AuraState) -> str:
    if state.is_gaming:
        return "focus"
    if not state.user_present:
        return "eco"
    if state.cpu_percent < 30 and state.memory_available_mb > 8000:
        return "performance"
    return "balance"


def save_state(state: AuraState) -> Path:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / "latest.json"
    path.write_text(json.dumps(asdict(state), indent=2, default=str), encoding="utf-8")
    return path
