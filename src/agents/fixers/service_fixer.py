
"""Install Oneness as Windows service / scheduled tasks where possible."""
import subprocess
from pathlib import Path
from .base import FixerAgent

class ServiceFixer(FixerAgent):
    def run(self):
        self.log_finding("Checking admin privileges and service installation readiness.")
        is_admin = self._is_admin()
        self.log_finding(f"Running as admin: {is_admin}")
        if not is_admin:
            self.log_error("Cannot install Windows service without admin privileges.")
            self.log_recommendation("Right-click PowerShell and 'Run as administrator', then run scripts/integrations/install_windows_service.ps1")
            self.result.status = "needs_user"
            self.save_result()
            return self.result

        exe = Path(r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\publish\Oneness.Web.exe")
        if not exe.exists():
            self.log_finding("Published binary not found. Building release publish...")
            build = subprocess.run(["dotnet", "publish", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src\Oneness.Web\Oneness.Web.csproj", "-c", "Release", "-o", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\publish", "--self-contained", "false"], capture_output=True, text=True, timeout=180)
            if build.returncode != 0:
                self.log_error(f"Publish failed: {build.stderr[:500]}")
                self.result.status = "failed"
                self.save_result()
                return self.result
            self.log_action("Published Oneness.Web release build.")

        sc_create = subprocess.run(["sc.exe", "create", "OnenessWeb", "binPath=", str(exe), "start=", "auto", "obj=", "NT AUTHORITY\\LOCALSERVICE", "displayName=", "Oneness System Web Control Center"], capture_output=True, text=True, timeout=30)
        self.log_action(f"sc create output: {sc_create.stdout.strip()} {sc_create.stderr.strip()}")
        if sc_create.returncode != 0:
            self.log_finding("Service may already exist; attempting start.")
        sc_start = subprocess.run(["sc.exe", "start", "OnenessWeb"], capture_output=True, text=True, timeout=30)
        self.log_action(f"sc start output: {sc_start.stdout.strip()} {sc_start.stderr.strip()}")
        if sc_start.returncode == 0 or "already" in (sc_start.stdout + sc_start.stderr).lower():
            self.result.status = "fixed"
            self.log_finding("OnenessWeb Windows service installed/started.")
        else:
            self.result.status = "failed"
            self.log_error("Failed to start OnenessWeb service.")
            self.log_recommendation("Check Event Viewer > System for service start errors.")

        self.log_finding("Attempting to register daily scheduled tasks...")
        sched = subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\integrations\create_scheduled_tasks.ps1"], capture_output=True, text=True, timeout=60)
        self.log_action(f"Scheduled task output: {sched.stdout.strip()} {sched.stderr.strip()}")
        self.save_result()
        return self.result

    def _is_admin(self):
        try:
            import ctypes
            return ctypes.windll.shell32.IsUserAnAdmin() != 0
        except Exception:
            return False
