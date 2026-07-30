"""SignalForge-Lite: low-frequency Polymarket data fetcher that respects gaming mode."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from finance.polymarket import top_opportunities, save_markets_snapshot
from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "signalforge_lite.log"
GAMING_LOCK = MEMORY_DIR / "gaming.lock"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | SIGNALFORGE-LITE | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def is_gaming() -> bool:
    if not GAMING_LOCK.exists():
        return False
    return GAMING_LOCK.read_text(encoding="utf-8").strip() == "true"


def main():
    while True:
        try:
            if is_gaming():
                log("Gaming mode active; skipping market scan")
                time.sleep(600)  # 10 min during gaming
                continue
            markets = top_opportunities(n=10)
            path = save_markets_snapshot(markets, filename="lite_signals.json")
            log(f"Saved {len(markets)} opportunities to {path}")
            time.sleep(1800)  # 30 min normally
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(600)


if __name__ == "__main__":
    main()
