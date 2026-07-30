"""IdleCleaner: cleans temp/cache when user is idle and not gaming."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "idlecleaner.log"
GAMING_LOCK = MEMORY_DIR / "gaming.lock"


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | IDLECLEANER | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def is_gaming() -> bool:
    if not GAMING_LOCK.exists():
        return False
    return GAMING_LOCK.read_text(encoding="utf-8").strip() == "true"


def clean_temp_files(days: int = 7) -> int:
    import tempfile
    freed = 0
    temp_dir = Path(tempfile.gettempdir())
    for item in temp_dir.rglob("*"):
        try:
            if item.is_file() and (datetime.now(timezone.utc).timestamp() - item.stat().st_ctime) > days * 86400:
                freed += item.stat().st_size
                item.unlink()
        except Exception:
            pass
    return freed


def main():
    while True:
        if is_gaming():
            time.sleep(30)
            continue
        try:
            latest = json.loads((MEMORY_DIR / "latest.json").read_text(encoding="utf-8"))
            idle = latest.get("mouse_idle_seconds", 0)
            if idle > 600:  # 10 minutes idle
                freed = clean_temp_files()
                log(f"Cleaned {freed / (1024*1024):.1f} MB from temp")
                time.sleep(3600)  # once per hour max
            else:
                time.sleep(60)
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(60)


if __name__ == "__main__":
    main()
