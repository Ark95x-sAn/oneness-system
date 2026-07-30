
"""Check network connectivity to AI services and DNS."""
import socket
import subprocess
from pathlib import Path
from .base import FixerAgent

class NetworkFixer(FixerAgent):
    HOSTS = [
        ("anthropic.com", 443),
        ("claude.ai", 443),
        ("api.openai.com", 443),
        ("github.com", 443),
        ("www.blackbox.ai", 443),
        ("www.perplexity.ai", 443),
        ("registry.npmjs.org", 443),
    ]

    def run(self):
        self.log_finding("Checking network reachability to AI backends.")
        all_ok = True
        for host, port in self.HOSTS:
            ok = self._tcp_check(host, port)
            self.log_finding(f"{host}:{port} -> {'reachable' if ok else 'UNREACHABLE'}")
            if not ok:
                all_ok = False
                self.log_recommendation(f"Verify firewall/DNS/VPN settings for {host}.")
        for host, _ in self.HOSTS:
            try:
                ip = socket.gethostbyname(host)
                self.log_finding(f"DNS {host} -> {ip}")
            except Exception as e:
                self.log_error(f"DNS failed for {host}: {e}")
                all_ok = False
        try:
            result = subprocess.run(["powershell", "-Command", "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object Name, InterfaceDescription"], capture_output=True, text=True, timeout=10)
            self.log_finding(f"Active adapters:\n{result.stdout.strip()}")
        except Exception as e:
            self.log_error(f"Could not list adapters: {e}")
        self.result.status = "ok" if all_ok else "partial"
        self.save_result()
        return self.result

    def _tcp_check(self, host: str, port: int, timeout: float = 5.0):
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except Exception:
            return False
