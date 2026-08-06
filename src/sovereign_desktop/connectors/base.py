"""Base connector interface for Sovereign Desktop Ops HQ."""
import subprocess
from abc import ABC, abstractmethod

class Connector(ABC):
    def __init__(self, app_id: str, config: dict):
        self.app_id = app_id
        self.config = config

    @abstractmethod
    def status(self, running_patterns=None) -> dict:
        """Return current app status."""
        ...

    @abstractmethod
    def launch(self, confirmed: bool = False) -> dict:
        """Launch the app if confirmed."""
        ...

    def _run(self, cmd, shell: bool = False):
        try:
            proc = subprocess.Popen(cmd, shell=shell, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, cwd=r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem")
            return {"ok": True, "pid": proc.pid}
        except Exception as e:
            return {"ok": False, "error": str(e)}
