"""BuildBooster: detects build/coding activity and signals resource optimizers to back off."""
from __future__ import annotations

import json
import time
from pathlib import Path
from datetime import datetime, timezone

from ..state import MEMORY_DIR

LOG = MEMORY_DIR / "buildbooster.log"

BUILD_PROCESSES = [
    "dotnet.exe", "msbuild.exe", "node.exe", "npm.exe", "vite.exe", "webpack",
    "python.exe", "pytest.exe", "cargo.exe", "rustc.exe", "go.exe", "gcc.exe"
]


def log(msg: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).isoformat()} | BUILDBOOSTER | {msg}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def detect_build() -> dict:
    try:
        import psutil
        count = 0
        names = []
        for p in psutil.process_iter(["name"]):
            name = p.info.get("name", "").lower()
            if any(bp in name for bp in BUILD_PROCESSES):
                count += 1
                names.append(name)
        active = count > 0
        return {
            "build_active": active,
            "process_count": count,
            "sample_processes": list(set(names))[:5],
            "boost_requested": active,
        }
    except Exception as e:
        return {"build_active": False, "process_count": 0, "sample_processes": [], "boost_requested": False, "error": str(e)}


def main():
    while True:
        try:
            state = detect_build()
            log(f"build_active={state['build_active']} procs={state['process_count']} boost={state['boost_requested']}")
            state_path = MEMORY_DIR / "buildbooster_state.json"
            state_path.write_text(json.dumps(state), encoding="utf-8")
            time.sleep(60)
        except Exception as e:
            log(f"Error: {e}")
            time.sleep(60)


if __name__ == "__main__":
    main()
