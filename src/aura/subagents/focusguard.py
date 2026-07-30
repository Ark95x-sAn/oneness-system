"""FocusGuard: protects deep-work sessions by suppressing non-urgent interruptions."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "focusguard.log"

DEEP_WORK_APPS = [
    "code.exe", "codex.exe", "claude.exe", "devenv.exe", "rider64.exe",
    "notion.exe", "obsidian.exe", "chrome.exe", "firefox.exe", "msedge.exe"
]

PRODUCTIVITY_SITES = ["github.com", "perplexity.ai", "chatgpt.com", "claude.ai", "notion.so", "linear.app"]


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | FOCUSGUARD | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def classify_context(active_window: str, idle_seconds: int) -> dict:
    lower = active_window.lower()
    in_deep_work = any(app in lower for app in DEEP_WORK_APPS)
    in_productive_site = any(site in lower for site in PRODUCTIVITY_SITES)
    if in_deep_work and idle_seconds < 300:
        return {"mode": "deep", "priority": "protect", "suppress_cleaners": True}
    if in_productive_site and idle_seconds < 300:
        return {"mode": "research", "priority": "light", "suppress_cleaners": False}
    return {"mode": "idle", "priority": "maintenance", "suppress_cleaners": False}


def main():
    while True:
        try:
            latest = json.loads((MEMORY_DIR / "latest.json").read_text(encoding="utf-8"))
            active = latest.get("active_window", "")
            idle = latest.get("mouse_idle_seconds", 0)
            context = classify_context(active, idle)
            log(f"mode={context['mode']} window='{active[:60]}' idle={idle}s suppress={context['suppress_cleaners']}")
            state_path = MEMORY_DIR / "focusguard_state.json"
            state_path.write_text(json.dumps(context), encoding="utf-8")
            time.sleep(60)
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(60)


if __name__ == "__main__":
    main()
