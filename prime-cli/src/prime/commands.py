"""Command implementations for prime CLI."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from . import config
from .api import OnenessAPI


def _run(cmd: list[str], cwd: Path | None = None, shell: bool = False, wait: bool = True) -> dict[str, Any]:
    """Run a process and return structured result."""
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd) if cwd else None,
            shell=shell,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if wait:
            stdout, stderr = proc.communicate(timeout=120)
            return {
                "ok": proc.returncode == 0,
                "returncode": proc.returncode,
                "stdout": stdout.strip(),
                "stderr": stderr.strip(),
            }
        return {"ok": True, "pid": proc.pid, "stdout": "", "stderr": ""}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def cmd_doctor(json_mode: bool = False) -> dict[str, Any]:
    """Diagnose Oneness System readiness."""
    api = OnenessAPI()
    result: dict[str, Any] = {
        "root": str(config.ROOT),
        "web_url": config.WEB_URL,
        "venv_python": str(config.VENV_PYTHON),
        "checks": {},
    }
    result["checks"]["root_exists"] = config.ROOT.exists()
    result["checks"]["venv_python"] = config.VENV_PYTHON.exists()
    result["checks"]["orchestrator_script"] = config.ORCHESTRATOR.exists()
    result["checks"]["run_script"] = config.RUN_SCRIPT.exists()
    result["checks"]["admin_script"] = config.ADMIN_SCRIPT.exists()
    result["checks"]["auth_script"] = config.AUTH_SCRIPT.exists()
    result["checks"]["fixer_script"] = config.FIXER_SCRIPT.exists()
    result["checks"]["config_yaml"] = config.CONFIG_YAML.exists()

    try:
        health = api.health()
        result["checks"]["web_api"] = {"ok": True, "health": health}
    except Exception as e:
        result["checks"]["web_api"] = {"ok": False, "error": str(e)}

    try:
        docker = shutil.which("docker")
        result["checks"]["docker_cli"] = bool(docker)
    except Exception as e:
        result["checks"]["docker_cli"] = {"ok": False, "error": str(e)}

    result["ready"] = all(
        v if isinstance(v, bool) else v.get("ok", False)
        for v in result["checks"].values()
    )

    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print("Prime Fire Council Diagnostic")
        print("=" * 40)
        for k, v in result["checks"].items():
            status = "[OK]" if (v if isinstance(v, bool) else v.get("ok", False)) else "❌"
            print(f"{status} {k}")
        print("=" * 40)
        print(f"Overall ready: {result['ready']}")
    return result


def cmd_start(json_mode: bool = False) -> dict[str, Any]:
    """Start Prime Fire Council: orchestrator + web dashboard."""
    import os
    env = os.environ.copy()
    env["DEMO_MODE"] = "true"
    env["ONENESS_SYSTEM_ROOT"] = str(config.ROOT)

    # Start orchestrator
    orch_proc = subprocess.Popen(
        [str(config.VENV_PYTHON), str(config.ORCHESTRATOR), "--demo"],
        cwd=str(config.ROOT),
        env=env,
        creationflags=subprocess.CREATE_NO_WINDOW,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Start web dashboard
    web_proc = subprocess.Popen(
        ["dotnet", "run", "--project", str(config.ROOT / "src" / "Oneness.Web"), "--urls", config.WEB_URL],
        cwd=str(config.ROOT),
        env=env,
        creationflags=subprocess.CREATE_NO_WINDOW,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    result = {
        "ok": True,
        "orchestrator_pid": orch_proc.pid,
        "web_pid": web_proc.pid,
    }

    api = OnenessAPI()
    web_ready = False
    web_error = None
    for attempt in range(15):
        time.sleep(3)
        try:
            api.health()
            web_ready = True
            break
        except Exception as e:
            web_error = str(e)
    result["web_ready"] = web_ready
    result["web_error"] = web_error if not web_ready else None

    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        if web_ready:
            print(f"Prime Fire Council active at {config.WEB_URL}")
        else:
            print(f"Started processes but web dashboard not ready yet: {web_error}")
    return result


def cmd_stop() -> dict[str, Any]:
    """Stop Oneness web and orchestrator processes safely."""
    killed: list[dict[str, Any]] = []
    targets = _find_oneness_processes()
    for p in targets:
        try:
            p.kill()
            killed.append({"name": p.info.get("name"), "pid": p.pid})
        except Exception as e:
            killed.append({"name": p.info.get("name"), "pid": p.pid, "error": str(e)})
    print(f"Stopped {len(killed)} Oneness process(es).")
    return {"stopped": killed}


def _find_oneness_processes():
    """Find only processes that belong to the Oneness System."""
    try:
        import psutil
        matches = []
        for p in psutil.process_iter(["pid", "name", "cmdline"]):
            cmdline = " ".join(p.info.get("cmdline") or [])
            name = p.info.get("name") or ""
            if name.lower() == "oneness.web":
                matches.append(p)
            elif name.lower() == "dotnet.exe" and "oneness" in cmdline.lower():
                matches.append(p)
            elif name.lower() == "python.exe" and "oneness_orchestrator" in cmdline.lower():
                matches.append(p)
        return matches
    except Exception:
        return []


def cmd_status(json_mode: bool = False) -> dict[str, Any]:
    """Show system status."""
    api = OnenessAPI()
    result: dict[str, Any] = {"web_url": config.WEB_URL}
    try:
        result["health"] = api.health()
        result["agents"] = api.agents()
        result["tools"] = api.tools()
        result["projects"] = api.projects()
        result["web_ok"] = True
    except Exception as e:
        result["web_ok"] = False
        result["error"] = str(e)
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        if result["web_ok"]:
            print(f"Oneness Web: {config.WEB_URL} ✅")
            print(f"Agents: {len(result['agents'])}")
            print(f"Tools: {len(result['tools'])}")
            print(f"Projects: {len(result['projects'])}")
        else:
            print(f"Oneness Web unreachable: {result['error']}")
    return result


def cmd_agents_list(json_mode: bool = False) -> list[dict[str, Any]]:
    api = OnenessAPI()
    agents = api.agents()
    if json_mode:
        print(json.dumps(agents, indent=2, default=str))
    else:
        print("Agents:")
        for a in agents:
            print(f"  - {a.get('id', '?')}: {a.get('status', 'unknown')}")
    return agents


def cmd_agents_tick(agent_id: str, json_mode: bool = False) -> dict[str, Any]:
    api = OnenessAPI()
    result = api.tick(agent_id)
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"Ticked {agent_id}: {result}")
    return result


def cmd_fix(json_mode: bool = False) -> dict[str, Any]:
    """Run all fixer agents."""
    result = _run([str(config.VENV_PYTHON), str(config.FIXER_SCRIPT)], cwd=config.ROOT)
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(result["stdout"] if result["ok"] else result.get("stderr", result.get("error", "fix failed")))
    return result


def cmd_auth() -> dict[str, Any]:
    """Launch auth helper scripts."""
    result = _run([str(config.AUTH_SCRIPT)], cwd=config.ROOT, shell=True, wait=False)
    print("Auth launcher started. Complete sign-in in the windows that appear, then return here.")
    return result


def cmd_service_install() -> dict[str, Any]:
    """Launch admin installer (user must approve UAC)."""
    if not config.ADMIN_SCRIPT.exists():
        return {"ok": False, "error": f"Admin script missing: {config.ADMIN_SCRIPT}"}
    print("Launching admin installer. Approve the UAC prompt to install the Windows service.")
    result = _run([
        "powershell.exe",
        "-ExecutionPolicy", "Bypass",
        "-File", str(config.ADMIN_SCRIPT),
    ], wait=False)
    return result


def cmd_web() -> dict[str, Any]:
    """Open Oneness Web URL (best-effort via explorer)."""
    try:
        os.startfile(config.WEB_URL)
        print(f"Opened {config.WEB_URL}")
        return {"ok": True}
    except Exception as e:
        print(f"Could not open browser: {e}. Visit {config.WEB_URL} manually.")
        return {"ok": False, "error": str(e)}


def cmd_apps_list() -> dict[str, Any]:
    """Placeholder: requires Computer Use node_repl."""
    print("Computer Use squad not yet connected.")
    print("Restart Codex desktop app to enable node_repl, then run `prime apps` again.")
    return {"ok": False, "reason": "node_repl_unavailable"}


def cmd_install_skill(skill_path: str) -> dict[str, Any]:
    """Install a skill from GitHub into ~/.codex/skills."""
    installer = Path.home() / ".codex" / "skills" / ".system" / "skill-installer" / "scripts" / "install-skill-from-github.py"
    if not installer.exists():
        return {"ok": False, "error": f"Skill installer not found: {installer}"}
    result = _run([str(config.VENV_PYTHON), str(installer), "--repo", "openai/skills", "--path", skill_path])
    print(result["stdout"] if result["ok"] else result.get("stderr", result.get("error", "install failed")))
    return result


def cmd_review(target_path: str, json_mode: bool = False) -> dict[str, Any]:
    """Run a lightweight file review."""
    path = Path(target_path)
    if not path.exists():
        return {"ok": False, "error": f"Path not found: {target_path}"}
    # Very basic static scan
    issues: list[dict[str, Any]] = []
    for f in path.rglob("*"):
        if f.is_file() and f.suffix in {".py", ".cs", ".js", ".ts"}:
            text = f.read_text(errors="ignore")
            if "password" in text.lower() or "secret" in text.lower() or "token" in text.lower():
                issues.append({"file": str(f), "kind": "secret_keyword", "note": "Contains sensitive keyword; verify no hardcoded secrets."})
            if "TODO" in text or "FIXME" in text:
                issues.append({"file": str(f), "kind": "todo", "note": "Contains TODO/FIXME."})
    result = {"target": str(path), "issues": issues}
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"Reviewed {target_path}: {len(issues)} issue(s)")
        for i in issues[:20]:
            print(f"  [{i['kind']}] {i['file']}")
    return result


def cmd_scan(json_mode: bool = False) -> dict[str, Any]:
    """Trigger VS project scan."""
    api = OnenessAPI()
    result = api.scan_projects()
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"Project scan started: {result}")
    return result


def cmd_build(path: str, configuration: str = "Release", json_mode: bool = False) -> dict[str, Any]:
    """Build a project via Oneness API."""
    api = OnenessAPI()
    result = api.build_project(path, configuration)
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print(f"Build result: {result}")
    return result


def cmd_speedup(json_mode: bool = False) -> dict[str, Any]:
    """Launch PC optimization (requires admin UAC for deep cleanup)."""
    shortcut_candidates = [
        Path.home() / "OneDrive" / "Desktop" / "Speed Up PC.lnk",
        Path.home() / "Desktop" / "Speed Up PC.lnk",
    ]
    shortcut = next((s for s in shortcut_candidates if s.exists()), shortcut_candidates[0])
    result = {"shortcut": str(shortcut), "exists": shortcut.exists(), "non_admin_applied": True}
    # Apply non-admin tweaks immediately
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", 0, winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, "EnableTransparency", 0, winreg.REG_DWORD, 0)
    except Exception as e:
        result["transparency_error"] = str(e)
    if json_mode:
        print(json.dumps(result, indent=2, default=str))
    else:
        print("Applied non-admin performance tweaks.")
        print(f"For deep cleanup, right-click this shortcut and choose 'Run as administrator': {shortcut}")
    return result

def cmd_aura(action: str, json_mode: bool = False) -> dict[str, Any]:
    """Control Aura ambient subagents."""
    import json as _json
    import psutil
    controller = config.ROOT / "src" / "aura" / "controller.py"
    result: dict[str, Any] = {"action": action}
    if action in ("start", "stop", "status"):
        r = _run([str(config.VENV_PYTHON), str(controller), action], cwd=config.ROOT)
        try:
            result["controller"] = _json.loads(r["stdout"]) if r["ok"] else {"ok": False, "stderr": r.get("stderr"), "error": r.get("error")}
        except Exception:
            result["controller"] = r
    elif action == "state":
        state_file = config.ROOT / "memory" / "aura" / "latest.json"
        if state_file.exists():
            result["state"] = _json.loads(state_file.read_text(encoding="utf-8"))
        else:
            result["state"] = None
    elif action == "logs":
        log_dir = config.ROOT / "memory" / "aura"
        logs = []
        if log_dir.exists():
            for f in log_dir.glob("*.log"):
                logs.append({"name": f.name, "size": f.stat().st_size, "lines": len(f.read_text(encoding="utf-8").splitlines())})
        result["logs"] = logs
    else:
        result["error"] = f"Unknown aura action: {action}"
    if json_mode:
        print(_json.dumps(result, indent=2, default=str))
    else:
        print(f"Aura action: {action}")
        print(_json.dumps(result, indent=2, default=str))
    return result

def cmd_markets(json_mode: bool = False) -> dict[str, Any]:
    """Fetch top Polymarket opportunities."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from finance.polymarket import top_opportunities, save_markets_snapshot
        ops = top_opportunities(n=10)
        path = save_markets_snapshot(ops, filename="prime_signals.json")
        result = {"ok": True, "count": len(ops), "path": str(path), "opportunities": ops}
    except Exception as e:
        result = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(result, indent=2, default=str))
    else:
        print(f"Top {result.get('count', 0)} Polymarket opportunities")
        for op in result.get("opportunities", [])[:5]:
            print(f"  - {op.get('question', '?')[:60]}... vol={op.get('volume24h')} liq={op.get('liquidity')}")
    return result


def cmd_compound(
    principal: float,
    rate: float,
    years: float,
    contributions: float = 0.0,
    json_mode: bool = False,
) -> dict[str, Any]:
    """Compound interest calculator."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from finance.compound import compound
        result = compound(principal, rate, years, contributions=contributions)
        data = {
            "principal": result.principal,
            "rate_annual": result.rate_annual,
            "years": result.years,
            "contributions": result.contributions,
            "final_value": result.final_value,
            "total_contributions": result.total_contributions,
            "total_interest": result.total_interest,
        }
    except Exception as e:
        data = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(data, indent=2, default=str))
    else:
        fv = data.get("final_value", 0); tc = data.get("total_contributions", 0); ti = data.get("total_interest", 0)
        print(f"Final value: ${fv:,.2f} | Contributions: ${tc:,.2f} | Interest: ${ti:,.2f}")
    return data

def cmd_852(intent: str = "rise", json_mode: bool = False) -> dict[str, Any]:
    """Activate or resonate the 852 anti-self-sabotage sigil."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from progression.sigil import resonate
        state = resonate(intent)
        data = {
            "code": state.code,
            "activated": state.activated,
            "resonance_count": state.resonance_count,
            "last_intent": state.last_intent,
            "timestamp": state.timestamp,
        }
    except Exception as e:
        data = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(data, indent=2, default=str))
    else:
        print(f"852 resonated | count={data.get('resonance_count')} | intent={data.get('last_intent')}")
    return data


def cmd_gates(json_mode: bool = False) -> dict[str, Any]:
    """Evaluate all progression gates and bosses."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from progression.gates import evaluate_gates, current_boss
        gates = evaluate_gates()
        boss = current_boss()
        data = {"gates": gates, "current_boss": boss}
    except Exception as e:
        data = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(data, indent=2, default=str))
    else:
        print(f"Gates evaluated: {len(data.get('gates', []))}")
        if data.get("current_boss"):
            b = data["current_boss"]
            print(f"Current boss: Gate {b['gate']} — {b['boss']['name']}")
            print(f"Action: {b['action']}")
            print(f"Reward: {b['reward']}")
        else:
            print("All gates cleared.")
    return data


def cmd_boss(json_mode: bool = False) -> dict[str, Any]:
    """Show current gate boss."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from progression.gates import current_boss
        boss = current_boss()
        data = boss or {"message": "No active boss — all gates cleared or system not ready"}
    except Exception as e:
        data = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(data, indent=2, default=str))
    else:
        if "boss" in data:
            print(f"Boss: {data['boss']['name']} (Gate {data['gate']})")
            print(f"Pattern: {data['boss']['pattern']}")
            print(f"Defeat: {data['action']}")
        else:
            print(data.get("message"))
    return data


def cmd_sabotage(json_mode: bool = False) -> dict[str, Any]:
    """Detect self-sabotage patterns."""
    import json as _json
    try:
        sys.path.insert(0, str(config.ROOT / "src"))
        from progression.selfsaboteur import report
        data = report()
    except Exception as e:
        data = {"ok": False, "error": str(e)}
    if json_mode:
        print(_json.dumps(data, indent=2, default=str))
    else:
        print(f"Self-sabotage patterns found: {data.get('count', 0)}")
        for p in data.get("patterns", []):
            print(f"  [{p['severity'].upper()}] {p['name']}: {p['signal']}")
            print(f"      Counter: {p['counterspell']}")
    return data