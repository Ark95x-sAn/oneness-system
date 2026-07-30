
"""Detect which AI tools need authentication and build login helper scripts."""
import subprocess
from pathlib import Path
from .base import FixerAgent

class AuthFixer(FixerAgent):
    def run(self):
        self.log_finding("Checking authentication state for external AI tools.")
        tools = [
            ("Claude Desktop", "claude", "claude --version"),
            ("Claude Code", "npx", "npx @anthropic-ai/claude-code --version"),
            ("OpenClaw", "openclaw", "openclaw --version"),
            ("Codex CLI", "npx", "npx openai-codex --version"),
            ("GitHub CLI", "gh", "gh auth status"),
            ("Docker Hub", "docker", "docker info"),
        ]
        for name, exe, check in tools:
            try:
                result = subprocess.run(check, shell=True, capture_output=True, text=True, timeout=20)
                if result.returncode == 0:
                    self.log_finding(f"{name}: CLI reachable (auth state unknown without API call).")
                else:
                    self.log_finding(f"{name}: CLI responded but check returned non-zero (likely not authenticated).")
                    self.log_recommendation(f"Open {name} and complete sign-in / run 'gh auth login' / set API keys in .env.")
            except Exception as e:
                self.log_error(f"{name}: could not run '{check}': {e}")
                self.log_recommendation(f"Install or configure {name}.")
        self._write_auth_helpers()
        self.log_action("Generated auth helper scripts in scripts/fixers/")
        self.result.status = "partial"
        self.save_result()
        return self.result

    def _write_auth_helpers(self):
        helpers = {
            "scripts/fixers/auth_claude_desktop.bat": 'start "" "https://claude.ai/login"\necho Sign in to Claude Desktop, then return here.\npause\n',
            "scripts/fixers/auth_blackbox.bat": 'start "" "https://app.blackbox.ai/login"\necho Sign in to Blackbox AI, then return here.\npause\n',
            "scripts/fixers/auth_perplexity.bat": 'start "" "https://www.perplexity.ai"\necho Sign in to Perplexity, then return here.\npause\n',
            "scripts/fixers/auth_gh_copilot.bat": '@echo off\ngh auth login\ngh copilot --version\npause\n',
            "scripts/fixers/auth_openai_api.bat": '@echo off\necho Add OPENAI_API_KEY to OnenessSystem/.env\nnotepad C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\.env\npause\n',
            "scripts/fixers/auth_anthropic_api.bat": '@echo off\necho Add ANTHROPIC_API_KEY to OnenessSystem/.env\nnotepad C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\.env\npause\n',
        }
        for path, content in helpers.items():
            p = self.memory.parent / path
            p.parent.mkdir(parents=True, exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(content)
