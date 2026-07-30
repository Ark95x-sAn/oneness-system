
"""Scan, validate, and build all VS/VSCode projects found on the system."""
import json
import subprocess
from pathlib import Path
from .base import FixerAgent

class VsProjectFixer(FixerAgent):
    def run(self):
        self.log_finding("Scanning for Visual Studio / VS Code projects and building them.")
        scan_output = self.memory / "logs" / "vs_projects.json"
        if not scan_output.exists():
            self.log_finding("No existing project scan. Running scanner...")
            result = subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\scripts\integrations\scan_vs_projects.ps1"], capture_output=True, text=True, timeout=120)
            self.log_action(f"Scanner output: {result.stdout.strip()} {result.stderr.strip()}")
        if not scan_output.exists():
            self.log_error("Project scanner did not produce output.")
            self.result.status = "failed"
            self.save_result()
            return self.result
        try:
            with open(scan_output, "r", encoding="utf-8-sig") as f:
                data = json.load(f)
        except Exception as e:
            self.log_error(f"Failed to parse vs_projects.json: {e}")
            self.result.status = "failed"
            self.save_result()
            return self.result

        projects_to_build = []
        for root in data:
            for p in root.get("CSharpProjects", []):
                projects_to_build.append(Path(p["FullName"]))
            for s in root.get("Solutions", []):
                projects_to_build.append(Path(s["FullName"]))

        if not projects_to_build:
            self.log_finding("No .csproj/.sln projects found to build.")
            self.result.status = "ok"
            self.save_result()
            return self.result

        any_failed = False
        for proj in projects_to_build:
            self.log_finding(f"Building {proj}...")
            build = subprocess.run(["dotnet", "build", str(proj), "-c", "Release"], capture_output=True, text=True, timeout=180)
            if build.returncode == 0:
                self.log_action(f"Build OK: {proj}")
            else:
                any_failed = True
                self.log_error(f"Build failed: {proj} -> {build.stderr[:400]}")
        self.result.status = "ok" if not any_failed else "partial"
        self.save_result()
        return self.result

