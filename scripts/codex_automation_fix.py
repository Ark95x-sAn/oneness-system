#!/usr/bin/env python3
"""
Codex Automation Fix - Unified repair and health check for the Oneness System codex integration.

This script:
1. Diagnoses all codex-related components (CLI, config, plugins, MCP)
2. Auto-fixes known issues
3. Produces a structured report of what is working and what needs attention
4. Can be run standalone or as part of the prime fixer suite

Run:
    python scripts/codex_automation_fix.py [--auto]
"""
import json
import os
import shutil
import subprocess
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
MEMORY = ROOT / "memory"

def log(section, msg):
    prefix = f"[{section:>15}] {msg}"
    print(prefix)

def find_codex_exe():
    """Find the installed codex CLI executable."""
    base = Path(r"C:\Users\ArcXN\AppData\Local\OpenAI\Codex\bin")
    if base.exists():
        for v in sorted(base.iterdir(), reverse=True):
            exe = v / "codex.exe"
            if exe.exists():
                return str(exe)
    # Try PATH
    found = shutil.which("codex")
    if found:
        return found
    return None

def read_config_toml(path):
    """Simple TOML reader for config.toml (handles the subset we need)."""
    cfg = {}
    sections = ["root"]
    
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("[") and "=" not in stripped:
                section_name = stripped.strip("[]").strip()
                sections.append(section_name)
                cfg.setdefault(section_name, {})
            elif "=" in stripped:
                key, value = stripped.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"')
                cfg_key = f"{sections[-1]}.{key}" if len(sections) > 1 else key
                try:
                    if value.lower() in ("true", "false"):
                        value = value.lower() == "true"
                    else:
                        value = int(value)
                except (ValueError, AttributeError):
                    pass
                cfg[cfg_key] = value
    return cfg

def test_codex_version(codex_exe):
    """Test if codex CLI responds to --version."""
    try:
        r = subprocess.run(
            [codex_exe, "--version"],
            capture_output=True, text=True, timeout=15
        )
        return {
            "ok": r.returncode == 0,
            "output": r.stdout.strip(),
            "error": r.stderr.strip()[:200] if r.stderr else None
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timed out after 15s"}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def test_codex_health(codex_exe):
    """Test if codex CLI responds to a health check."""
    try:
        r = subprocess.run(
            [codex_exe, "--health"],
            capture_output=True, text=True, timeout=15
        )
        return {
            "ok": r.returncode == 0,
            "output": r.stdout.strip(),
            "error": r.stderr.strip()[:200] if r.stderr else None
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timed out after 15s"}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def check_sage_plugin(cfg):
    """Check sage plugin state from config."""
    result = {}
    
    # Check marketplace registration
    marketplaces = {k: v for k, v in cfg.items() if k.startswith("marketplaces.")}
    if "marketplaces.sage" in marketplaces:
        result["registered"] = True
        sage_section = {k.replace("marketplaces.sage.", ""): v 
                       for k, v in cfg.items() if k.startswith("marketplaces.sage.")}
        result["last_revision"] = sage_section.get("last_revision", "unknown")
        result["source_type"] = sage_section.get("source_type", "unknown")
    else:
        result["registered"] = False
    
    # Check sage plugin cache
    sage_cache = Path(r"C:\Users\ArcXN\.codex\plugins\cache\sage\sage")
    result["cache_exists"] = sage_cache.exists()
    
    if sage_cache.exists():
        hooks_path = sage_cache / "hooks" / "hooks.json"
        if hooks_path.exists():
            try:
                with open(hooks_path, "r") as f:
                    hooks_data = json.load(f)
                pre_hooks = len(hooks_data.get("hooks", {}).get("PreToolUse", []))
                post_hooks = len(hooks_data.get("hooks", {}).get("PostToolUse", []))
                session_hooks = len(hooks_data.get("hooks", {}).get("SessionStart", []))
                result["hooks_valid"] = True
                result["pre_hook_count"] = pre_hooks
                result["post_hook_count"] = post_hooks
                result["session_hook_count"] = session_hooks
                
                all_hooks = (
                    hooks_data.get("hooks", {}).get("PreToolUse", []) +
                    hooks_data.get("hooks", {}).get("PostToolUse", [])
                )
                bad_hooks = [h for m in all_hooks for h in m.get("hooks", []) if h.get("type") == "mcp_tool"]
                result["has_bad_hooks"] = len(bad_hooks) > 0
            except json.JSONDecodeError:
                result["hooks_valid"] = False
        else:
            result["hooks_exist"] = False
    
    # Check MCP server bundle
    mcp_bundle = sage_cache / "packages" / "claude-code" / "dist" / "mcp-server.cjs"
    result["mcp_server_exists"] = mcp_bundle.exists()
    
    return result

def check_config_health(cfg):
    """Check config.toml health."""
    result = {}
    
    mp = cfg.get("model_provider", "not set")
    result["model_provider"] = mp
    
    model = cfg.get("model", "not set")
    result["model"] = model
    
    # Ollama connectivity check
    if "ollama" in str(mp).lower():
        catalog_path = cfg.get("model_catalog_json", "")
        try:
            import urllib.request
            resp = urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5)
            result["ollama_reachable"] = True
            data = json.loads(resp.read())
            result["ollama_models_count"] = len(data.get("models", []))
        except Exception as e:
            result["ollama_reachable"] = False
            result["ollama_error"] = str(e)
    
    # Sandbox mode
    sandbox = cfg.get("sandbox_mode", "not set")
    result["sandbox_mode"] = sandbox
    
    return result

def run_fixes(cfg, auto=False):
    """Run automatic fixes. Returns list of actions taken."""
    actions = []
    
    # Fix: hooks if bad
    sage_hooks = Path(r"C:\Users\ArcXN\.codex\plugins\cache\sage\sage/hooks/hooks.json")
    if sage_hooks.exists():
        try:
            with open(sage_hooks, "r") as f:
                hooks_data = json.load(f)
            
            all_hooks = (
                hooks_data.get("hooks", {}).get("PreToolUse", []) +
                hooks_data.get("hooks", {}).get("PostToolUse", [])
            )
            bad_hooks = [h for m in all_hooks for h in m.get("hooks", []) if h.get("type") == "mcp_tool"]
            
            if bad_hooks and auto:
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
                bak = sage_hooks.parent / "hooks.json.bak"
                if not bak.exists():
                    try:
                        sage_hooks.replace(bak)
                    except Exception:
                        pass
                with open(sage_hooks, "w", encoding="utf-8") as f:
                    json.dump(fixed, f, indent=2)
                actions.append("Fixed hooks.json (removed unsupported mcp_tool hooks)")
        except Exception:
            pass
    
    return actions

def main():
    print("=" * 60)
    print("  CODEX AUTOMATION FIX - Oneness System Health Report")
    print("=" * 60)
    print()
    
    auto = "--auto" in os.sys.argv
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "codex": {},
        "config": {},
        "plugins": {},
        "integration": {},
        "issues": [],
        "actions_taken": [],
        "recommendations": []
    }
    
    # 1. Codex CLI health
    log("CODEX", "Diagnosing Codex CLI...")
    codex_exe = find_codex_exe()
    report["codex"]["cli_path"] = codex_exe or "not found"
    
    if codex_exe:
        version = test_codex_version(codex_exe)
        report["codex"]["version"] = version.get("output", "")
        report["codex"]["version_ok"] = version["ok"]
        
        if not version["ok"]:
            log("CODEX", f"VERSION FAIL: {version.get('error')}")
            report["issues"].append(f"Codex CLI version check failed: {version.get('error')}")
            report["recommendations"].append("Try reinstalling codex: npm install -g @openai/codex")
        else:
            log("CODEX", f"CLI OK: {version['output']}")
    else:
        log("CODEX", "CLI NOT FOUND")
        report["issues"].append("Codex CLI executable not found")
        report["recommendations"].append("Install Codex CLI via npm install -g @openai/codex")
    
    # 2. Config.toml health
    print()
    log("CONFIG", "Reading config.toml...")
    cfg_path = Path(r"C:\Users\ArcXN\.codex\config.toml")
    cfg = None
    
    if cfg_path.exists():
        cfg = read_config_toml(cfg_path)
        config_health = check_config_health(cfg)
        report["config"] = config_health
        
        log("CONFIG", f"Model provider: {config_health.get('model_provider')}")
        log("CONFIG", f"Active model: {config_health.get('model')}")
        
        if config_health.get("ollama_reachable"):
            log("CONFIG", f"Ollama reachable with {config_health.get('ollama_models_count')} models")
        else:
            log("CONFIG", "Ollama NOT reachable - model will fail to load")
            report["issues"].append("Ollama not responding at 127.0.0.1:11434")
            report["recommendations"].append("Start Ollama: ollama serve (or configure a different model_provider)")
        
        sandbox = config_health.get("sandbox_mode", "")
        log("CONFIG", f"Sandbox mode: {sandbox}")
    else:
        log("CONFIG", "config.toml NOT FOUND")
        report["issues"].append("Config.toml not found at ~/.codex/config.toml")
        report["recommendations"].append("Run codex in a terminal to generate config, or copy from another machine.")
    
    # 3. Plugin health
    print()
    log("PLUGINS", "Checking Sage plugin...")
    sage = check_sage_plugin(cfg) if cfg else {"error": "config not loaded"}
    report["plugins"]["sage"] = sage
    
    if isinstance(sage, dict):
        log("PLUGINS", f"Registered: {sage.get('registered', False)}")
        if sage.get("cache_exists"):
            log("PLUGINS", "Plugin cache exists")
            if not sage.get("hooks_valid", True) or sage.get("has_bad_hooks"):
                log("PLUGINS", "WARNING: hooks.json has issues")
                report["issues"].append("Sage hooks.json has problems")
                if auto:
                    actions = run_fixes(cfg, auto=True)
                    report["actions_taken"].extend(actions)
            else:
                log("PLUGINS", "hooks.json OK")
        elif sage.get("registered"):
            log("PLUGINS", "WARNING: Sage registered but cache missing - reinstall needed?")
            report["issues"].append("Sage plugin registered but cache not found")
            report["recommendations"].append("Uninstall and reinstall Sage plugin in Codex marketplace")
    
    # 4. Run automatic fixes
    print()
    if auto:
        log("FIXES", "Running automatic fixes...")
        if cfg is None:
            cfg = {}
        actions = run_fixes(cfg, auto=True)
        report["actions_taken"].extend(actions)
        for a in actions:
            log("FIXES", f"APPLIED: {a}")
    else:
        log("FIXES", "Run with --auto to apply fixes automatically")
    
    # 5. System integration checks
    print()
    log("SYSTEM", "Checking Oneness System integration...")
    
    fixer_script = ROOT / "scripts" / "run_all_fixers.py"
    report["integration"]["fixer_script_exists"] = fixer_script.exists()
    
    orchestrator = ROOT / "src" / "oneness_orchestrator.py"
    report["integration"]["orchestrator_exists"] = orchestrator.exists()
    
    venv_python = ROOT / "venv" / "Scripts" / "python.exe"
    report["integration"]["venv_python_ok"] = venv_python.exists()
    
    if not venv_python.exists():
        log("SYSTEM", "venv Python missing - activate your virtual environment")
        report["issues"].append("venv\\Scripts\\python.exe not found")
    else:
        log("SYSTEM", f"venv Python OK: {venv_python}")
    
    # Summary
    print()
    print("-" * 60)
    
    issues = report.get("issues", [])
    actions = report.get("actions_taken", [])
    
    if not issues and not report.get("recommendations"):
        log("STATUS", "ALL CHECKS PASSED - Codex automation is healthy")
    else:
        severity = 0
        if codex_exe is None:
            severity += 3
        if any("Ollama" in i for i in issues):
            severity += 2
        if any("hooks" in i.lower() for i in issues):
            severity += 1
        
        if severity >= 3:
            log("STATUS", "CRITICAL - Codex automation will NOT work without fixes")
        elif severity >= 2:
            log("STATUS", "WARNING - Codex automation has major issues")
        elif severity >= 1:
            log("STATUS", "DEGRADED - Some components need attention")
        
        if issues:
            print()
            for i in issues:
                log("ISSUE", i)
        
        if actions:
            print()
            for a in actions:
                log("FIXED", a)
        
        if report.get("recommendations"):
            print()
            log("NEXT STEPS", "Recommendations:")
            for r in report["recommendations"]:
                print(f"    - {r}")
    
    # Save report
    report_path = MEMORY / "logs" / "codex_automation_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, default=str)
    
    print()
    log("REPORT", f"Saved to {report_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
