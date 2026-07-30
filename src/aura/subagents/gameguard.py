"""GameGuard: protects gaming sessions by signaling other subagents to pause."""
from __future__ import annotations

import time
from pathlib import Path
from datetime import datetime, timezone

from ..watcher import AuraWatcher
from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "gameguard.log"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | GAMEGUARD | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def main():
    watcher = AuraWatcher(poll_seconds=2.0)
    gaming = False
    while True:
        state = watcher.run_once()
        if state.is_gaming and not gaming:
            gaming = True
            log("GAMING MODE ON — pausing background optimizers")
            # Write a signal file that other agents read
            (MEMORY_DIR / "gaming.lock").write_text("true", encoding="utf-8")
        elif not state.is_gaming and gaming:
            gaming = False
            log("GAMING MODE OFF — resuming background optimizers")
            (MEMORY_DIR / "gaming.lock").write_text("false", encoding="utf-8")
        time.sleep(2.0)


if __name__ == "__main__":
    main()
