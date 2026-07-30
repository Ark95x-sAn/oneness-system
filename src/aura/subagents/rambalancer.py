"""RAMBalancer: trims non-essential working sets when memory pressure rises."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "rambalancer.log"
GAMING_LOCK = MEMORY_DIR / "gaming.lock"
SAFELIST = {"cod", "oneness.web", "dotnet", "python", "node_repl", "codex-computer-use"}


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | RAMBALANCER | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def is_gaming() -> bool:
    if not GAMING_LOCK.exists():
        return False
    return GAMING_LOCK.read_text(encoding="utf-8").strip() == "true"


def trim_if_needed():
    try:
        import psutil
        mem = psutil.virtual_memory()
        if mem.percent < 85:
            return f"memory at {mem.percent}%, no trim needed"

        if is_gaming():
            return f"gaming mode active, skipping trim at {mem.percent}%"

        trimmed = []
        for p in psutil.process_iter(["pid", "name", "memory_info"]):
            name = p.info.get("name", "").lower()
            if any(safe in name for safe in SAFELIST):
                continue
            try:
                ws = p.info.get("memory_info", None)
                if ws and ws.rss > 100 * 1024 * 1024:  # >100MB
                    proc = psutil.Process(p.info["pid"])
                    # Only trim known safe background apps
                    if any(bg in name for bg in ["onenote", "teams", "notion", "slack", "discord", "spotify", "chrome", "edge"]):
                        proc.memory_info()  # touch to ensure access
                        # Cannot truly trim WS from Python; log recommendation
                        trimmed.append(name)
            except Exception:
                pass
        return f"memory at {mem.percent}%, candidates: {trimmed}"
    except Exception as e:
        return f"error: {e}"


def main():
    while True:
        result = trim_if_needed()
        log(result)
        time.sleep(60)


if __name__ == "__main__":
    main()
