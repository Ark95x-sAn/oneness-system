"""Low-overhead Windows signal collectors for Aura."""
from __future__ import annotations

import ctypes
import subprocess
from typing import Any


def get_active_window_info() -> dict[str, Any]:
    try:
        user32 = ctypes.windll.user32
        hwnd = user32.GetForegroundWindow()
        length = user32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, title, length + 1)

        pid = ctypes.c_uint()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))

        proc_name = "unknown"
        try:
            proc = subprocess.run(["tasklist", "/fi", f"PID eq {pid.value}", "/fo", "csv", "/nh"], capture_output=True, text=True, timeout=2)
            if proc.stdout.strip():
                proc_name = proc.stdout.split(',"')[1].strip('"')
        except Exception:
            pass

        return {"title": title.value, "process": proc_name, "pid": pid.value}
    except Exception as e:
        return {"title": "", "process": "unknown", "pid": 0, "error": str(e)}


def get_mouse_idle_seconds() -> int:
    try:
        class LASTINPUTINFO(ctypes.Structure):
            _fields_ = [("cbSize", ctypes.c_uint), ("dwTime", ctypes.c_ulong)]
        lii = LASTINPUTINFO()
        lii.cbSize = ctypes.sizeof(LASTINPUTINFO)
        ctypes.windll.user32.GetLastInputInfo(ctypes.byref(lii))
        millis = ctypes.windll.kernel32.GetTickCount() - lii.dwTime
        return int(millis / 1000)
    except Exception:
        return 0
