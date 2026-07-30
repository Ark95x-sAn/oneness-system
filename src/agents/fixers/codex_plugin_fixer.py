"""Diagnose and repair Codex plugin / MCP startup issues."""
import json
import os
import subprocess
from pathlib import Path
from .base import FixerAgent

class CodexPluginFixer(FixerAgent):
    # Common codex installation paths
    CODEX_BIN_PATHS = [
        Path(r"C:\Users\ArcXN\AppData\Local\OpenAI\Codex\bin\codex.exe"),
    ]
    PLUGIN_ROOT = Path(r"C:\Users\ArcXN\.codex\plugins\cache\sage\sage")

    def run(self):
        self.log_finding("Diagnosing Codex automation environment.")
        
        # 1. Check codex CLI binary exists and is runnable
        codex_exe = self._find_codex_exe()
        if codex_exe:
            self.log_finding(f"Codex CLI found at: {codex_exe}")
            try:
                r = subprocess.run(
                    [str(codex_exe), "--version"],
                    capture_output=True, text=True, timeout=15
                )
                if r.returncode == 0:
                    self.log_finding(f"Codex CLI responds: {r.stdout.strip()}")
                else:
                    self.log_error(f"Codex CLI failed to report version: {r.stderr.strip()[:200]}")
            except Exception as e:
                self.log_error(f"Codex CLI version check failed: {e}")
        else:
            self.log_error("Codex CLI executable not found in expected locations.")
            self.log_recommendation("Reinstall Codex via: npm install -g @openai/codex")

        # 2. Check config.toml for model provider and plugin state
        config_path = Path(r"C:\Users\ArcXN\.codex\config.toml")
        if config_path.exists():
            cfg_text = config_path.read_text(encoding="utf-8")
            
            # Extract model_provider
            mp_line = [l for l in cfg_text.splitlines() if l.strip().startswith("model_provider")]
            if mp_line:
                provider = mp_line[0].split("=", 1)[1].strip().strip('"')
                self.log_finding(f"Active model provider: {provider}")
            
            # Check sage marketplace entry
            if "[marketplaces.sage]" in cfg_text:
                self.log_finding("Sage marketplace plugin is registered in config.")
                rev_match = [l.strip() for l in cfg_text.splitlines() 
                            if "last_revision" in l and "sage" not in l]
                # Find sage revision from the section
                in_sage = False
                sage_rev = None
                for line in cfg_text.splitlines():
                    if "[marketplaces.sage]" in line:
                        in_sage = True
                    elif in_sage and "last_revision" in line:
                        sage_rev = line.split("=")[1].strip().strip('"')
                        break
                self.log_finding(f"Sage plugin revision: {sage_rev or 'unknown'}")
            else:
                self.log_error("Sage marketplace plugin not found in config.toml.")
            
            # Check model_catalog_json (ollama models)
            catalog_match = [l for l in cfg_text.splitlines() if "model_catalog_json" in l]
            if catalog_match:
                cat_path = catalog_match[0].split("=", 1)[1].strip().strip('"')
                cat_file = Path(cat_path)
                if cat_file.exists():
                    self.log_finding(f"Ollama model catalog exists: {cat_file}")
                else:
                    self.log_error(f"Ollama model catalog missing: {cat_path}")
                    self.log_recommendation("Run 'codex' once in a terminal to regenerate the ollama model list.")
        else:
            self.log_error("config.toml not found at ~/.codex/config.toml")

        # 3. Check Sage plugin files (if installed)
        if self.PLUGIN_ROOT.exists():
            hooks_dir = self.PLUGIN_ROOT / "hooks"
            hooks_path = hooks_dir / "hooks.json"
            if hooks_path.exists():
                try:
                    with open(hooks_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    pre = data.get("hooks", {}).get("PreToolUse", [])
                    post = data.get("hooks", {}).get("PostToolUse", [])
                    has_bad = any(
                        any(h.get("type") == "mcp_tool" for h in m.get("hooks", []))
                        for m in pre + post
                    )
                    if has_bad:
                        self.log_error("hooks.json contains unsupported mcp_tool hooks.")
                        self._fix_hooks(hooks_path)
                        self.log_action("Rewrote hooks.json to use command-type SessionStart only.")
                    else:
                        self.log_finding("hooks.json hooks are valid (no unsupported types).")
                except json.JSONDecodeError as e:
                    self.log_error(f"hooks.json is invalid JSON: {e}")
                    self._fix_hooks(hooks_path)
            else:
                self.log_finding("No hooks.json found in Sage plugin.")
            
            # Check MCP server bundle
            server_js = self.PLUGIN_ROOT / "packages" / "claude-code" / "dist" / "mcp-server.cjs"
            if server_js.exists():
                self.log_finding(f"Sage MCP server bundle exists: {server_js}")
            else:
                self.log_finding("Sage MCP server bundle not present (may be normal for recent versions).")
        else:
            self.log_finding("Sage plugin cache not found at expected path.")

        # 4. Check node_repl runtime
        node_repl_paths = [
            Path(r"C:\Users\ArcXN\AppData\Local\OpenAI\Codex\runtimes\cua_node"),
            Path(r"C:\Users\ArcXN\.codex\packages\standalone"),
            Path(r"C:\Users\ArcXN\.codex\node_repl"),
        ]
        found_node_repl = any(p.exists() for p in node_repl_paths)
        self.log_finding(f"node_repl runtime available: {found_node_repl}")
        
        # 5. Check computer-use pipe / chrome plugin state
        cu_path = Path(r"C:\Users\ArcXN\.codex\computer-use")
        if cu_path.exists():
            self.log_finding("Computer-use directory present.")
        else:
            self.log_finding("Computer-use not yet initialized (will initialize on first use).")

        # Overall assessment
        errors = len(self.result.errors)
        if errors == 0 and codex_exe:
            self.result.status = "ok"
        elif any("needs" in r.lower() for r in self.result.recommendations):
            self.result.status = "needs_user"
        else:
            self.result.status = "partial"
        
        self.save_result()
        return self.result

    def _find_codex_exe(self) -> Path | None:
        # Check explicit paths
        for p in self.CODEX_BIN_PATHS:
            if p.exists():
                return p
        # Check latest versioned bin dir
        base = Path(r"C:\Users\ArcXN\AppData\Local\OpenAI\Codex\bin")
        if base.exists():
            versions = sorted(base.iterdir(), reverse=True)
            for v in versions:
                exe = v / "codex.exe"
                if exe.exists():
                    return exe
        # Check PATH via codex.cmd
        try:
            import shutil
            found = shutil.which("codex")
            if found and found.endswith(".cmd"):
                self.log_finding(f"Codex available in PATH: {found}")
                return None  # CLI works via PATH, no exe fix needed
        except Exception:
            pass
        return None

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
                                "command": 'node "${CLAUDE_PLUGIN_ROOT}/packages/claude-code/dist/session-start.cjs"',
                                "timeout": 30,
                                "statusMessage": "Sage: Scanning installed plugins..."
                            }
                        ]
                    }
                ]
            }
        }
        bak = hooks_path.parent / "hooks.json.bak"
        if not bak.exists():
            try:
                hooks_path.replace(bak)
            except Exception:
                pass
        with open(hooks_path, "w", encoding="utf-8") as f:
            json.dump(fixed, f, indent=2)
