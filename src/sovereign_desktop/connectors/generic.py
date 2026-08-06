"""Generic connector driven by registry entries."""
import subprocess
import pathlib
from .base import Connector

class GenericConnector(Connector):
    def status(self, running_patterns=None) -> dict:
        pattern = self.config.get("process_pattern", "")
        running = False
        if running_patterns and pattern:
            proc_name = pattern.lower()
            running = any(proc_name in (p.get("ProcessName", "") or "").lower() for p in running_patterns)
        detected = running or self._is_installed()
        return {
            "id": self.app_id,
            "display": self.config.get("display"),
            "family": self.config.get("family"),
            "running": running,
            "detected": detected,
            "launch_type": self.config.get("launch_type"),
            "launch_value": self.config.get("launch_value"),
            "connection_methods": self.config.get("connection_methods", [])
        }

    def _is_installed(self) -> bool:
        lt = self.config.get("launch_type")
        lv = self.config.get("launch_value", "")
        if lt == "command":
            try:
                subprocess.check_output(["where", lv], stderr=subprocess.DEVNULL, timeout=5)
                return True
            except Exception:
                return False
        if lt in ("exe", "tray_exe", "cmd"):
            return pathlib.Path(lv).exists()
        return bool(lv)

    def launch(self, confirmed: bool = False) -> dict:
        if not confirmed:
            return {
                "ok": False,
                "status": "preview",
                "message": f"Launch {self.app_id} requires confirmation.",
                "launch_type": self.config.get("launch_type"),
                "launch_value": self.config.get("launch_value")
            }
        lt = self.config.get("launch_type")
        lv = self.config.get("launch_value", "")
        if lt == "command":
            return self._run(lv, shell=True)
        if lt in ("exe", "tray_exe", "cmd"):
            return self._run([lv])
        if lt == "browser_url":
            return self._run(["start", lv], shell=True)
        if lt == "shell_app":
            return self._run(["explorer.exe", f"shell:AppsFolder\\{lv}"])
        return {"ok": False, "error": "unknown launch_type"}
