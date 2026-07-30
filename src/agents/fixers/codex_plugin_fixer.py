"""Diagnose and repair Codex plugin / MCP startup issues."""
import json
import os
import subprocess
from pathlib import Path
from .base import FixerAgent

class CodexPluginFixer(FixerAgent):
    PLUGIN_ROOT = Path(r"C:\Users\ArcXN\.codex\plugins\cache\sage\sage\0.11.0")

    def run(self):
        self.log_finding("Diagnosing Codex plugin / MCP startup failures.")
        hooks_path = self.PLUGIN_ROOT / "hooks" / "hooks.json"
        backup_path = self.PLUGIN_ROOT / "hooks" / "hooks.json.bak"
        if backup_path.exists():
            self.log_finding("Sage hooks.json backup exists from earlier fix.")
        if hooks_path.exists():
            try:
                with open(hooks_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                pre = data.get("hooks", {}).get("PreToolUse", [])
                post = data.get("hooks", {}).get("PostToolUse", [])
                has_bad = any(any(h.get("type") == "mcp_tool" for h in m.get("hooks", [])) for m in pre + post)
                if has_bad:
                    self.log_finding("hooks.json still contains unsupported mcp_tool hooks.")
                    self._fix_hooks(hooks_path)
                    self.log_action("Rewrote hooks.json to use command-type SessionStart only.")
                else:
                    self.log_finding("hooks.json has no unsupported mcp_tool hooks.")
            except json.JSONDecodeError as e:
                self.log_error(f"hooks.json is invalid JSON: {e}")
                self._fix_hooks(hooks_path)
                self.log_action("Recreated hooks.json with valid command-type hooks.")

        server_js = self.PLUGIN_ROOT / "packages" / "claude-code" / "dist" / "mcp-server.cjs"
        if server_js.exists():
            self.log_finding(f"Sage MCP server bundle exists: {server_js}")
            try:
                proc = subprocess.Popen(["node", str(server_js)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                init = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "fixer", "version": "1.0"}}}) + "\n"
                proc.stdin.write(init)
                proc.stdin.flush()
                proc.stdin.close()
                proc.wait(timeout=10)
                out = proc.stdout.read()
                if "initialize" in out:
                    self.log_finding("Sage MCP server responds to manual initialize.")
                else:
                    self.log_error("Sage MCP server did not return expected initialize response.")
                    self.log_recommendation("The Sage plugin may need an update from the marketplace. Try uninstalling and reinstalling it in Codex.")
            except Exception as e:
                self.log_error(f"MCP server test failed: {e}")
        else:
            self.log_error("Sage MCP server bundle missing.")
            self.log_recommendation("Reinstall Sage plugin from Codex marketplace.")

        node_repl_paths = [Path(r"C:\Users\ArcXN\.codex\packages\standalone"), Path(r"C:\Users\ArcXN\.codex\node_repl")]
        found_node_repl = any(p.exists() for p in node_repl_paths)
        self.log_finding(f"node_repl path candidates found: {found_node_repl}")
        if not found_node_repl:
            self.log_error("node_repl runtime path not found.")
            self.log_recommendation("Restart Codex desktop app or reinstall the primary runtime to restore node_repl.")

        issues = len(self.result.errors)
        if issues == 0:
            self.result.status = "fixed"
        elif any("needs" in r.lower() for r in self.result.recommendations):
            self.result.status = "needs_user"
        else:
            self.result.status = "partial"
        self.save_result()
        return self.result

    def _fix_hooks(self, hooks_path: Path):
        fixed = {
            "hooks": {
                "PreToolUse": [],
                "PostToolUse": [],
                "SessionStart": [
                    {
                        "hooks": [
                            {
                                "type": "command",
                                "command": "node \"${CLAUDE_PLUGIN_ROOT}/packages/claude-code/dist/session-start.cjs\"",
                                "timeout": 30,
                                "statusMessage": "Sage: Scanning installed plugins..."
                            }
                        ]
                    }
                ]
            }
        }
        if not (hooks_path.parent / "hooks.json.bak").exists():
            try:
                hooks_path.replace(hooks_path.parent / "hooks.json.bak")
            except Exception:
                pass
        with open(hooks_path, "w", encoding="utf-8") as f:
            json.dump(fixed, f, indent=2)
