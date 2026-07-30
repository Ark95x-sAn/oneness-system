"""TradeWatch: monitors existing positions and alerts on large moves."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "tradewatch.log"
PORTFOLIO_FILE = MEMORY_DIR.parent / "polymarket" / "portfolio.json"
ALERT_THRESHOLD_PCT = 10.0


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | TRADEWATCH | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def load_portfolio() -> list[dict]:
    if not PORTFOLIO_FILE.exists():
        return []
    return json.loads(PORTFOLIO_FILE.read_text(encoding="utf-8"))


def check_positions():
    portfolio = load_portfolio()
    if not portfolio:
        return "no open positions"
    alerts = []
    for pos in portfolio:
        current = pos.get("current_price", pos.get("entry_price", 0))
        entry = pos.get("entry_price", current)
        if entry > 0:
            move_pct = abs((current - entry) / entry) * 100
            if move_pct >= ALERT_THRESHOLD_PCT:
                alerts.append(f"{pos.get('market','?')}: {move_pct:.1f}% move")
    return "; ".join(alerts) if alerts else f"{len(portfolio)} positions stable"


def main():
    while True:
        try:
            result = check_positions()
            log(result)
            time.sleep(300)  # 5 minutes
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(300)


if __name__ == "__main__":
    main()
