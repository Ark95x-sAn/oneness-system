"""reporter.py — Unified status report generator for the Operations Mind.

Takes the latest cycle findings and snapshots and produces a comprehensive
JSON status report with severity breakdown, metrics, and recommendations.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from . import REPORTS_DIR, now_iso, write_json


def generate_report(state, reports_dir=None):
    """Generate a unified status report from the latest cycle state."""
    reports_dir = reports_dir or REPORTS_DIR
    reports_dir.mkdir(parents=True, exist_ok=True)

    findings = state.get("current_findings", [])
    snapshots = state.get("snapshots", {})
    health_score = state.get("health_score", 0)

    # Classify findings
    critical = [f for f in findings if f.get("severity") == "critical"]
    warnings = [f for f in findings if f.get("severity") == "warning"]
    info = [f for f in findings if f.get("severity") == "info"]

    # Build report
    ts = now_iso()
    report = {
        "generated_at": ts,
        "health_score": health_score,
        "health_status": _health_label(health_score),
        "summary": {
            "total_findings": len(findings),
            "critical": len(critical),
            "warnings": len(warnings),
            "info": len(info),
        },
        "snapshots": snapshots,
        "findings": {
            "critical": [_summarize_finding(f) for f in critical],
            "warnings": [_summarize_finding(f) for f in warnings],
            "info": [_summarize_finding(f) for f in info],
        },
        "recommendations": _generate_recommendations(findings, snapshots),
        "cycles_run": state.get("cycles_run", 0),
        "last_cycle": state.get("last_cycle"),
    }

    # Save report
    filename = f"report-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.json"
    report_path = reports_dir / filename
    write_json(report_path, report)

    # Also save as latest
    latest_path = reports_dir / "latest-report.json"
    write_json(latest_path, report)

    return {
        "report_path": str(report_path),
        "latest_path": str(latest_path),
        "health_score": health_score,
        "health_status": report["health_status"],
        "total_findings": len(findings),
    }


def _health_label(score):
    if score >= 85:
        return "EXCELLENT"
    elif score >= 70:
        return "GOOD"
    elif score >= 50:
        return "FAIR"
    elif score >= 30:
        return "POOR"
    else:
        return "CRITICAL"


def _summarize_finding(f):
    return {
        "type": f.get("type"),
        "title": f.get("title"),
        "description": f.get("description"),
        "risk_score": f.get("risk_score"),
        "roi_score": f.get("roi_score"),
    }


def _generate_recommendations(findings, snapshots):
    """Generate actionable recommendations from findings."""
    recs = []

    for f in findings:
        ftype = f.get("type", "")
        sev = f.get("severity", "info")

        if ftype == "cpu_critical" or ftype == "cpu_high":
            recs.append({
                "priority": "high" if sev == "critical" else "medium",
                "action": "Investigate top CPU processes and consider stopping resource hogs",
                "safe": True,
                "command": "python -m src.ops_mind.mind --cycle  # re-check after action",
            })
        elif ftype == "ram_critical" or ftype == "ram_high":
            recs.append({
                "priority": "high" if sev == "critical" else "medium",
                "action": "Close memory-heavy applications or browser tabs",
                "safe": True,
                "command": None,
            })
        elif ftype == "disk_critical" or ftype == "disk_low":
            recs.append({
                "priority": "high" if sev == "critical" else "medium",
                "action": "Run disk cleanup to reclaim temp/scratch files",
                "safe": False,
                "command": ".\\disk-cleanup-helper.ps1 -Reclaim",
                "note": "Requires user approval — modifies files",
            })
        elif ftype == "services_stopped":
            stopped = f.get("stopped_services", [])
            recs.append({
                "priority": "high" if sev == "critical" else "low",
                "action": f"Review stopped services: {', '.join(stopped)}",
                "safe": True,
                "command": f"Get-Service -Name {','.join(stopped)} | Format-Table",
            })
        elif ftype == "reboot_pending":
            recs.append({
                "priority": "medium",
                "action": "Restart the computer to complete pending Windows updates",
                "safe": False,
                "command": "shutdown /r /t 0",
                "note": "Requires user approval — closes all applications",
            })
        elif ftype == "network_unreachable":
            recs.append({
                "priority": "medium",
                "action": f"Check network connectivity to {f.get('title', 'unknown host')}",
                "safe": True,
                "command": "ipconfig /flushdns; Test-NetConnection 8.8.8.8",
            })
        elif ftype == "dns_failure":
            recs.append({
                "priority": "high",
                "action": "Restart DNS client service or check DNS settings",
                "safe": False,
                "command": "Restart-Service -Name Dnscache -Force",
                "note": "Requires user approval — restarts network service",
            })
        elif ftype == "process_high_cpu":
            proc = f.get("process", "?")
            if proc in ("vmmemWSL", "vmmem"):
                recs.append({
                    "priority": "medium",
                    "action": "Shut down WSL to reduce CPU usage",
                    "safe": False,
                    "command": "wsl --shutdown",
                    "note": "Requires user approval — kills all WSL/Linux processes",
                })
            elif proc == "OneDrive":
                recs.append({
                    "priority": "low",
                    "action": "Pause OneDrive sync if CPU pressure persists",
                    "safe": False,
                    "command": None,
                    "note": "OneDrive sync is a background task",
                })

    return recs