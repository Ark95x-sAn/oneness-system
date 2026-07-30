"""Aura watcher daemon: polls Windows state and writes recommendations."""
from __future__ import annotations

import time
from datetime import datetime, timezone

from .state import AuraState, detect_gaming, recommend_mode, save_state
from .windows_signals import get_active_window_info, get_mouse_idle_seconds

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False


class AuraWatcher:
    def __init__(self, poll_seconds: float = 5.0):
        self.poll_seconds = poll_seconds
        self.last_state: AuraState | None = None

    def _cpu_mem(self) -> tuple[float, float]:
        if not HAS_PSUTIL:
            return 0.0, 0.0
        cpu = psutil.cpu_percent(interval=0.5)
        mem = psutil.virtual_memory()
        return cpu, mem.available / (1024 * 1024)

    def sample(self) -> AuraState:
        window = get_active_window_info()
        cpu, mem_mb = self._cpu_mem()
        idle = get_mouse_idle_seconds()

        try:
            running = {p.info["name"].lower() for p in psutil.process_iter(["name"])} if HAS_PSUTIL else set()
        except Exception:
            running = set()

        is_gaming = detect_gaming(window.get("title", ""), window.get("process", ""), running)
        user_present = idle < 300

        state = AuraState(
            timestamp=datetime.now(timezone.utc).isoformat(),
            is_gaming=is_gaming,
            active_window_title=window.get("title", ""),
            active_process=window.get("process", ""),
            cpu_percent=round(cpu, 1),
            memory_available_mb=round(mem_mb, 1),
            mouse_idle_seconds=idle,
            keyboard_idle_seconds=idle,
            user_present=user_present,
            recommended_mode="",
        )
        state.recommended_mode = recommend_mode(state)
        self.last_state = state
        return state

    def run_once(self) -> AuraState:
        state = self.sample()
        save_state(state)
        return state

    def run_loop(self) -> None:
        while True:
            self.run_once()
            time.sleep(self.poll_seconds)


def main():
    watcher = AuraWatcher(poll_seconds=5.0)
    watcher.run_loop()


if __name__ == "__main__":
    main()
