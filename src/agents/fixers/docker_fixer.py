
"""Diagnose and attempt to start Docker Desktop/engine."""
import os
import subprocess
import time
from pathlib import Path
from .base import FixerAgent

class DockerFixer(FixerAgent):
    def run(self):
        self.log_finding("Checking Docker Desktop installation and engine state.")
        docker_path = self._which("docker")
        if not docker_path:
            self.log_error("Docker CLI not found on PATH.")
            self.log_recommendation("Install Docker Desktop from https://www.docker.com/products/docker-desktop")
            self.result.status = "needs_user"
            self.save_result()
            return self.result
        self.log_finding(f"Docker CLI found: {docker_path}")

        daemon_ok = self._run(["docker", "version"])
        if daemon_ok:
            self.log_finding("Docker daemon is already running.")
            self.result.status = "ok"
            self.save_result()
            return self.result

        self.log_finding("Docker daemon not responding. Checking Docker Desktop process.")
        desktop_running = self._check_process("Docker Desktop")
        if not desktop_running:
            self.log_finding("Docker Desktop is not running. Attempting to launch.")
            desktop_exe = self._find_docker_desktop()
            if desktop_exe and Path(desktop_exe).exists():
                self._run_async([desktop_exe])
                self.log_action(f"Launched Docker Desktop: {desktop_exe}")
                time.sleep(10)
            else:
                self.log_error("Docker Desktop executable not found at expected location.")
                self.log_recommendation("Install Docker Desktop or add it to PATH.")
                self.result.status = "needs_user"
                self.save_result()
                return self.result

        service_status = self._run_powershell("Get-Service com.docker.service | Select-Object Status")
        self.log_finding(f"com.docker.service status check: {service_status.strip()}")

        for attempt in range(1, 4):
            time.sleep(5)
            daemon_ok = self._run(["docker", "version"])
            if daemon_ok:
                self.log_action(f"Docker daemon responded after attempt {attempt}.")
                self.result.status = "fixed"
                self.save_result()
                return self.result

        self.log_error("Docker daemon still not responding after launch attempts.")
        self.log_recommendation("Start Docker Desktop manually, ensure WSL2 backend is enabled, or run wsl --update.")
        self.result.status = "needs_user"
        self.save_result()
        return self.result

    def _which(self, name: str):
        paths = os.environ.get("PATH", "").split(os.pathsep)
        for p in paths:
            candidate = Path(p) / name
            if candidate.exists():
                return str(candidate)
        return None

    def _run(self, cmd: list[str]):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            return result.returncode == 0
        except Exception as e:
            self.log_error(f"Command failed: {' '.join(cmd)} -> {e}")
            return False

    def _run_async(self, cmd: list[str]):
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _check_process(self, name: str):
        result = subprocess.run(["powershell", "-Command", f"Get-Process '{name}' -ErrorAction SilentlyContinue | Select-Object -First 1"], capture_output=True, text=True)
        return name in result.stdout or (result.returncode == 0 and result.stdout.strip() != "")

    def _find_docker_desktop(self):
        for c in [r"C:\Program Files\Docker\Docker\Docker Desktop.exe", r"C:\Program Files\Docker\Docker\DockerDesktop.exe"]:
            if Path(c).exists():
                return c
        return None

    def _run_powershell(self, cmd: str):
        try:
            result = subprocess.run(["powershell", "-Command", cmd], capture_output=True, text=True, timeout=15)
            return result.stdout + result.stderr
        except Exception as e:
            return str(e)

