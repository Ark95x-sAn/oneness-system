"""Detect which AI tools need authentication and build login helper scripts."""
import subprocess
from pathlib import Path
from .base import FixerAgent

class AuthFixer(FixerAgent):
    def run(self):
        self.log_finding("Checking authentication state for external AI tools.")
        
        # Check each tool using the actual CLI paths on this system
        codex_exe = self._find_codex_exe()
        
        tools = [
            ("Claude Desktop", "claude", "claude --version"),
            ("Claude Code", "claude-code", "claude --version"),
            ("OpenClaw", "openclaw", "openclaw --version"),
            ("Codex CLI", codex_exe or "codex", self._codex_check_cmd()),
            ("GitHub CLI", "gh", "gh auth status"),
            ("Docker Hub", "docker", "docker info"),
        ]
        
        for name, exe, check in tools:
            try:
                # For codex, also check version if auth fails
                result = subprocess.run(check, shell=True, capture_output=True, text=True, timeout=20)
                if result.returncode == 0:
                    self.log_finding(f"{name}: CLI reachable and responding OK.")
                else:
                    stderr = result.stderr.strip()[:100] if result.stderr else "no output"
                    if "auth" in name.lower() or "codex" in name.lower():
                        self.log_finding(f"{name}: CLI responds but auth check returned {result.returncode} ({stderr}).")
                        self.log_recommendation(f"Open {name} and complete sign-in, or set required API keys in .env.")
                    else:
                        self.log_finding(f"{name}: CLI responded with exit code {result.returncode}.")
            except subprocess.TimeoutExpired:
                self.log_error(f"{name}: command timed out (20s).")
                self.log_recommendation(f"Check if {name} service/process is running.")
            except FileNotFoundError:
                self.log_error(f"{name}: CLI not found ({exe}). Install or add to PATH.")
                self.log_recommendation(f"Install or configure {name}.")
            except Exception as e:
                self.log_error(f"{name}: could not check: {e}")
        
        self._write_auth_helpers()
        self.log_action("Generated auth helper scripts in scripts/fixers/")
        self.result.status = "ok" if not self.result.errors else "partial"
        self.save_result()
        return self.result

    def _find_codex_exe(self):
        """Find the codex CLI executable."""
        base = Path(r"C:\Users\ArcXN\AppData\Local\OpenAI\Codex\bin")
        if base.exists():
            for v in sorted(base.iterdir(), reverse=True):
                exe = v / "codex.exe"
                if exe.exists():
                    return str(exe)
        return None

    def _codex_check_cmd(self):
        """Return the command to check codex CLI."""
        codex_exe = self._find_codex_exe()
        if codex_exe:
            return f'"{codex_exe}" --version'
        return "codex --version"

    def _write_auth_helpers(self):
        helpers = {
            "scripts/fixers/auth_claude_desktop.bat": '@echo off\nstart "" "https://claude.ai/login"\necho Sign in to Claude Desktop, then return here.\npause\n',
            "scripts/fixers/auth_blackbox.bat": '@echo off\nstart "" "https://app.blackbox.ai/login"\necho Sign in to Blackbox AI, then return here.\npause\n',
            "scripts/fixers/auth_perplexity.bat": '@echo off\nstart "" "https://www.perplexity.ai"\necho Sign in to Perplexity, then return here.\npause\n',
            "scripts/fixers/auth_gh_copilot.bat": '@echo off\ngh auth login\ngh copilot --version\npause\n',
            "scripts/fixers/auth_openai_api.bat": '@echo off\necho Add OPENAI_API_KEY to OnenessSystem/.env\nnotepad C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\.env\npause\n',
            "scripts/fixers/auth_anthropic_api.bat": '@echo off\necho Add ANTHROPIC_API_KEY to OnenessSystem/.env\nnotepad C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\.env\npause\n',
        }
        for path, content in helpers.items():
            p = self.memory.parent / path
            p.parent.mkdir(parents=True, exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(content)
