"""Self-saboteur detector: finds patterns where the user or system undermines itself."""
from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MEMORY_DIR = Path(__file__).resolve().parent.parent.parent / "memory" / "progression"
ROOT = Path(__file__).resolve().parent.parent.parent


@dataclass
class SabotagePattern:
    name: str
    signal: str
    severity: str  # low, medium, high
    evidence: list[str]
    counterspell: str


def detect_self_sabotage() -> list[SabotagePattern]:
    findings: list[SabotagePattern] = []

    # 1. Admin installer not run
    service_log = ROOT / "memory" / "logs" / "admin_install.log"
    if not service_log.exists():
        findings.append(SabotagePattern(
            name="Unfinished Foundation",
            signal="OnenessWeb Windows service never installed despite admin approval",
            severity="high",
            evidence=["admin_install.log missing"],
            counterspell="Right-click 'Oneness Admin Install' desktop shortcut → Run as administrator",
        ))

    # 2. .env still placeholder
    env_file = ROOT / ".env"
    if env_file.exists() and "your-openai-key" in env_file.read_text(encoding="utf-8"):
        findings.append(SabotagePattern(
            name="Empty Vault",
            signal="API keys still placeholders",
            severity="high",
            evidence=[".env contains 'your-openai-key'"],
            counterspell="Edit .env with real OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.",
        ))

    # 3. Codex not restarted to bind node_repl
    node_repl_pipe = Path(r"\\.\pipe\codex-computer-use-0280cef0-3f17-46fc-9312-511434c775d6")
    if not node_repl_pipe.exists():
        findings.append(SabotagePattern(
            name="Unbound Hand",
            signal="Computer Use node_repl pipe not present; desktop automation unavailable",
            severity="medium",
            evidence=["named pipe missing"],
            counterspell="Restart Codex desktop app so node_repl/Sage/MCP_DOCKER reinitialize",
        ))

    # 4. Heavy background load while gaming (only flag if user already said to protect game)
    try:
        import psutil
        gaming = any(p.name().lower() in {"cod.exe", "warzone.exe", "modernwarfare.exe"} for p in psutil.process_iter(["name"]))
        if gaming:
            non_essential_heavy = []
            for p in psutil.process_iter(["name", "memory_info"]):
                name = p.info.get("name", "").lower()
                mem_mb = (p.info.get("memory_info").rss // (1024 * 1024)) if p.info.get("memory_info") else 0
                if mem_mb > 200 and name not in {"cod.exe", "oneness.web", "dotnet", "python", "explorer.exe", "msmpeng.exe"}:
                    if name in {"xboxpcapp.exe", "phoneexperiencehost.exe", "openclaw.tray.winui.exe", "teams.exe", "notion.exe", "chatgpt classic.exe"}:
                        non_essential_heavy.append(f"{name} ({mem_mb}MB)")
            if len(non_essential_heavy) >= 2:
                findings.append(SabotagePattern(
                    name="The Load Legion",
                    signal="Multiple heavy background apps competing while gaming",
                    severity="medium",
                    evidence=non_essential_heavy[:5],
                    counterspell="Close or minimize heavy apps before launching CoD; Aura GameGuard will skip them when active",
                ))
    except Exception:
        pass

    # 5. Skipped health checks / meta-agent stale
    meta_log = ROOT / "memory" / "logs" / "meta_agent.log"
    if meta_log.exists():
        # Check last line timestamp vs now
        try:
            last_line = meta_log.read_text(encoding="utf-8").strip().splitlines()[-1]
            ts = last_line.split(" | ")[0]
            last_dt = datetime.fromisoformat(ts)
            minutes_ago = (datetime.now(timezone.utc) - last_dt.replace(tzinfo=timezone.utc)).total_seconds() / 60
            if minutes_ago > 15:
                findings.append(SabotagePattern(
                    name="Silent Watchdog",
                    signal="Meta-agent has not run recently",
                    severity="low",
                    evidence=[f"last meta-agent run {minutes_ago:.0f} minutes ago"],
                    counterspell="Run `prime start` and confirm `Oneness-MetaAgent` task is Ready",
                ))
        except Exception:
            pass

    return findings


def save_sabotage_report(findings: list[SabotagePattern]) -> Path:
    import json
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / "sabotage_report.json"
    data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "count": len(findings),
        "patterns": [asdict(f) for f in findings],
    }
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


def report() -> dict[str, Any]:
    findings = detect_self_sabotage()
    path = save_sabotage_report(findings)
    return {"path": str(path), "count": len(findings), "patterns": [asdict(f) for f in findings]}
