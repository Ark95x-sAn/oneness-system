"""SelfSaboteurWatch: periodically scans for self-sabotage patterns and logs counterspells."""
from __future__ import annotations

import time
from datetime import datetime, timezone

from progression.selfsaboteur import report
from progression.sigil import resonate
from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "selfsaboteur_watch.log"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | SELFSABOTEUR-WATCH | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def main():
    # Activate 852 on first run
    state = resonate("rise")
    log(f"852 activated; resonance count = {state.resonance_count}")

    while True:
        try:
            result = report()
            if result["count"] == 0:
                log("No self-sabotage patterns detected")
            else:
                names = ", ".join(p["name"] for p in result["patterns"])
                log(f"Detected {result['count']} pattern(s): {names}")
            time.sleep(600)  # every 10 minutes
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(600)


if __name__ == "__main__":
    main()

