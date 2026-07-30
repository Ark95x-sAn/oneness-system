"""HealthWealth: tracks PC health metrics and correlates them with wealth activity capacity."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "healthwealth.log"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | HEALTHWEALTH | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def score_health(cpu: float, mem_pct: float, idle: int, is_gaming: bool) -> dict:
    # Higher score = more capacity for wealth-generating work
    base = 100
    base -= min(cpu, 60)  # CPU drag
    base -= min(mem_pct, 60)  # memory drag
    if is_gaming:
        base -= 30  # focus diverted
    if idle > 1800:
        base -= 20  # user away too long
    elif idle < 60:
        base += 10  # active and present
    return {
        "health_score": max(0, min(100, int(base))),
        "wealth_capacity": "high" if base >= 70 else "medium" if base >= 40 else "low",
        "recommendation": "run analysis" if base >= 70 else "wait or trade small" if base >= 40 else "rest and recover",
    }


def main():
    while True:
        try:
            latest = json.loads((MEMORY_DIR / "latest.json").read_text(encoding="utf-8"))
            score = score_health(
                latest.get("cpu_percent", 0),
                latest.get("memory_available_mb", 16000) / 16000 * 100,
                latest.get("mouse_idle_seconds", 0),
                latest.get("is_gaming", False),
            )
            log(f"Aura score: {score['health_score']} — wealth capacity: {score['wealth_capacity']} — {score['recommendation']}")
            time.sleep(300)  # 5 minutes
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(300)


if __name__ == "__main__":
    main()
