"""monitors.py — Unified health monitors for the Operations Mind.

Each monitor collects a specific domain of PC state and returns findings.
All monitors are read-only and safe to run at any time.
"""
import json
import os
import socket
import subprocess
import platform
from datetime import datetime, timezone
from pathlib import Path

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

from . import (
    CPU_CRITICAL, CPU_HIGH, RAM_CRITICAL, RAM_HIGH,
    DISK_LOW_PCT, DISK_CRITICAL_PCT, CRITICAL_SERVICES,
)


def _run_ps(cmd, timeout=20):
    """Run a PowerShell command and return (stdout, stderr, code)."""
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", cmd],
            capture_output=True, text=True, timeout=timeout, check=False,
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except Exception as exc:
        return "", str(exc), -1


def _json_ps(cmd, timeout=20):
    """Run a PowerShell command and parse JSON output."""
    stdout, stderr, code = _run_ps(cmd, timeout)
    try:
        return json.loads(stdout) if stdout else []
    except json.JSONDecodeError:
        return []


# ---------------------------------------------------------------------------
# Monitor: System Telemetry (CPU / RAM / Disk)
# ---------------------------------------------------------------------------
def monitor_telemetry():
    """Collect CPU, RAM, and disk usage."""
    findings = []

    if HAS_PSUTIL:
        cpu = psutil.cpu_percent(interval=0.5)
        mem = psutil.virtual_memory()
        ram_pct = mem.percent
        ram_used_gb = mem.used // (1024**3)
        ram_total_gb = mem.total // (1024**3)
    else:
        # Fallback to PowerShell
        stdout, _, _ = _run_ps(
            "(Get-CimInstance Win32_Processor).LoadPercentage"
        )
        cpu = float(stdout) if stdout else 0
        os_obj = _json_ps(
            "Get-CimInstance Win32_OperatingSystem | "
            "Select-Object @{N='TotalKB';E={$_.TotalVisibleMemorySize}}, "
            "@{N='FreeKB';E={$_.FreePhysicalMemory}} | ConvertTo-Json"
        )
        if os_obj:
            total_kb = os_obj.get("TotalKB", 0)
            free_kb = os_obj.get("FreeKB", 0)
            ram_pct = round((total_kb - free_kb) / total_kb * 100, 1) if total_kb else 0
            ram_total_gb = total_kb // (1024*1024) if total_kb else 0
            ram_used_gb = (total_kb - free_kb) // (1024*1024) if total_kb else 0
        else:
            ram_pct, ram_total_gb, ram_used_gb = 0, 0, 0

    # Disk
    disk_info = _json_ps(
        "Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\" | "
        "Select-Object @{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB,2)}}, "
        "@{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, "
        "@{N='PercentFree';E={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}} | ConvertTo-Json"
    )
    disk_free_gb = disk_info.get("FreeGB", 0) if disk_info else 0
    disk_total_gb = disk_info.get("SizeGB", 0) if disk_info else 0
    disk_pct_free = disk_info.get("PercentFree", 0) if disk_info else 0

    # CPU findings
    if cpu >= CPU_CRITICAL:
        findings.append({
            "type": "cpu_critical", "severity": "critical",
            "title": f"CPU critical at {cpu}%",
            "description": "System CPU is saturated. Investigate top processes.",
            "risk_score": 0.9, "roi_score": 5.0,
            "metric": cpu, "unit": "%",
        })
    elif cpu >= CPU_HIGH:
        findings.append({
            "type": "cpu_high", "severity": "warning",
            "title": f"CPU high at {cpu}%",
            "description": "System under CPU pressure.",
            "risk_score": 0.6, "roi_score": 3.0,
            "metric": cpu, "unit": "%",
        })

    # RAM findings
    if ram_pct >= RAM_CRITICAL:
        findings.append({
            "type": "ram_critical", "severity": "critical",
            "title": f"RAM critical at {ram_pct}%",
            "description": f"{ram_used_gb} GB / {ram_total_gb} GB used",
            "risk_score": 0.8, "roi_score": 4.0,
            "metric": ram_pct, "unit": "%",
        })
    elif ram_pct >= RAM_HIGH:
        findings.append({
            "type": "ram_high", "severity": "warning",
            "title": f"RAM high at {ram_pct}%",
            "description": f"{ram_used_gb} GB / {ram_total_gb} GB used",
            "risk_score": 0.5, "roi_score": 2.0,
            "metric": ram_pct, "unit": "%",
        })

    # Disk findings
    if disk_pct_free <= DISK_CRITICAL_PCT:
        findings.append({
            "type": "disk_critical", "severity": "critical",
            "title": f"Disk space critical: {disk_free_gb} GB free ({disk_pct_free}%)",
            "description": f"Only {disk_free_gb} GB free on C: out of {disk_total_gb} GB",
            "risk_score": 0.9, "roi_score": 4.0,
            "metric": disk_pct_free, "unit": "% free",
        })
    elif disk_pct_free <= DISK_LOW_PCT:
        findings.append({
            "type": "disk_low", "severity": "warning",
            "title": f"Disk space low: {disk_free_gb} GB free ({disk_pct_free}%)",
            "description": f"{disk_free_gb} GB free on C: out of {disk_total_gb} GB",
            "risk_score": 0.5, "roi_score": 2.0,
            "metric": disk_pct_free, "unit": "% free",
        })

    return {
        "monitor": "telemetry",
        "status": "ok",
        "snapshot": {
            "cpu_percent": cpu,
            "ram_percent": ram_pct,
            "ram_used_gb": ram_used_gb,
            "ram_total_gb": ram_total_gb,
            "disk_free_gb": disk_free_gb,
            "disk_total_gb": disk_total_gb,
            "disk_pct_free": disk_pct_free,
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# Monitor: Services
# ---------------------------------------------------------------------------
def monitor_services():
    """Check status of critical Windows services."""
    findings = []

    svc_json = _json_ps(
        "Get-Service | Where-Object { " +
        " -or ".join([f"$_.Name -eq '{s}'" for s in CRITICAL_SERVICES]) +
        " } | Select-Object Name, Status, StartType, DisplayName | ConvertTo-Json"
    )
    if isinstance(svc_json, dict):
        svc_json = [svc_json]

    stopped = [s for s in svc_json if s.get("Status") != 4 and s.get("Status") != "Running"]
    stopped_names = [s.get("Name", "?") for s in stopped]

    if stopped:
        sev = "critical" if any(n in ("WinDefend", "Dhcp", "Dnscache", "wscsvc") for n in stopped_names) else "warning"
        findings.append({
            "type": "services_stopped", "severity": sev,
            "title": f"{len(stopped)} critical service(s) not running",
            "description": json.dumps([{"name": s.get("Name"), "display": s.get("DisplayName"), "status": s.get("Status"), "start": s.get("StartType")} for s in stopped]),
            "risk_score": 0.6 if sev == "critical" else 0.3,
            "roi_score": 2.5,
            "stopped_services": stopped_names,
        })

    return {
        "monitor": "services",
        "status": "ok",
        "snapshot": {
            "total_checked": len(CRITICAL_SERVICES),
            "running": len(svc_json) - len(stopped),
            "stopped": len(stopped),
            "stopped_names": stopped_names,
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# Monitor: Top Processes
# ---------------------------------------------------------------------------
def monitor_processes():
    """Identify top CPU and memory consuming processes."""
    findings = []

    top = _json_ps(
        "Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 "
        "Name, Id, CPU, @{Name='WS_MB';Expression={[math]::Round($_.WorkingSet64/1MB,1)}} | ConvertTo-Json"
    )
    if isinstance(top, dict):
        top = [top]

    # Flag high-CPU processes
    for proc in top[:5]:
        name = proc.get("Name", "?")
        cpu_time = proc.get("CPU", 0)
        ws_mb = proc.get("WS_MB", 0)
        if name in ("vmmemWSL", "vmmem") and cpu_time > 50000:
            findings.append({
                "type": "process_high_cpu", "severity": "warning",
                "title": f"{name} has accumulated {cpu_time:.0f}s CPU time",
                "description": f"PID {proc.get('Id')}, RAM {ws_mb:.0f} MB. Consider shutting down WSL if not needed.",
                "risk_score": 0.5, "roi_score": 3.0,
                "process": name, "pid": proc.get("Id"),
            })
        elif name == "OneDrive" and cpu_time > 5000:
            findings.append({
                "type": "process_high_cpu", "severity": "info",
                "title": f"{name} sync using significant CPU ({cpu_time:.0f}s)",
                "description": f"PID {proc.get('Id')}. Consider pausing OneDrive sync if CPU pressure persists.",
                "risk_score": 0.2, "roi_score": 2.0,
                "process": name, "pid": proc.get("Id"),
            })

    return {
        "monitor": "processes",
        "status": "ok",
        "snapshot": {
            "top_processes": [{"name": p.get("Name"), "pid": p.get("Id"), "cpu_s": round(p.get("CPU", 0), 1), "ram_mb": p.get("WS_MB", 0)} for p in top[:10]],
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# Monitor: Network
# ---------------------------------------------------------------------------
def monitor_network():
    """Check network connectivity and DNS resolution."""
    findings = []
    hosts = [
        ("8.8.8.8", 53, "Google DNS"),
        ("github.com", 443, "GitHub"),
        ("www.google.com", 443, "Google Web"),
    ]

    results = []
    for host, port, label in hosts:
        ok = False
        try:
            with socket.create_connection((host, port), timeout=5):
                ok = True
        except Exception:
            pass
        results.append({"host": host, "port": port, "label": label, "reachable": ok})
        if not ok:
            findings.append({
                "type": "network_unreachable", "severity": "warning",
                "title": f"Cannot reach {label} ({host}:{port})",
                "description": "Check firewall, DNS, or VPN settings.",
                "risk_score": 0.4, "roi_score": 2.0,
            })

    # DNS check
    dns_ok = True
    try:
        socket.gethostbyname("google.com")
    except Exception:
        dns_ok = False
        findings.append({
            "type": "dns_failure", "severity": "critical",
            "title": "DNS resolution failing",
            "description": "Cannot resolve google.com. DNS service may be down.",
            "risk_score": 0.8, "roi_score": 3.0,
        })

    return {
        "monitor": "network",
        "status": "ok",
        "snapshot": {
            "checks": results,
            "dns_ok": dns_ok,
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# Monitor: Reboot / Windows Update
# ---------------------------------------------------------------------------
def monitor_reboot():
    """Check if a system reboot is pending."""
    findings = []
    pending = False
    reasons = []

    stdout, _, _ = _run_ps(
        "if (Test-Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing\\RebootPending') { 'CBS' }"
    )
    if "CBS" in stdout:
        pending = True
        reasons.append("CBS RebootPending")

    stdout, _, _ = _run_ps(
        "if (Test-Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\\RebootRequired') { 'WU' }"
    )
    if "WU" in stdout:
        pending = True
        reasons.append("WindowsUpdate RebootRequired")

    stdout, _, _ = _run_ps(
        "(Get-ItemProperty 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) -ne $null"
    )
    if "True" in stdout:
        pending = True
        reasons.append("PendingFileRenameOperations")

    if pending:
        findings.append({
            "type": "reboot_pending", "severity": "warning",
            "title": "System reboot pending",
            "description": f"Reasons: {', '.join(reasons)}. Restart to complete updates.",
            "risk_score": 0.5, "roi_score": 2.0,
            "reasons": reasons,
        })

    # Uptime
    try:
        stdout, _, _ = _run_ps(
            "(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime | "
            "Select-Object @{N='Days';E={$_.Days}}, @{N='Hours';E={$_.Hours}} | ConvertTo-Json"
        )
        uptime = json.loads(stdout) if stdout else {}
    except Exception:
        uptime = {}

    return {
        "monitor": "reboot",
        "status": "ok",
        "snapshot": {
            "reboot_pending": pending,
            "reasons": reasons,
            "uptime_days": uptime.get("Days", 0),
            "uptime_hours": uptime.get("Hours", 0),
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# Monitor: App Inventory
# ---------------------------------------------------------------------------
KNOWN_APPS = [
    {"name": "Google Chrome", "exe": r"C:\Program Files\Google\Chrome\Application\chrome.exe"},
    {"name": "Codex CLI", "exe": r"C:\Users\ArcXN\AppData\Roaming\npm\codex.cmd"},
    {"name": "Notion", "exe": r"C:\Users\ArcXN\AppData\Local\Programs\Notion\Notion.exe"},
    {"name": "Docker Desktop", "exe": r"C:\Program Files\Docker\Docker\Docker Desktop.exe"},
    {"name": "Claude Desktop", "exe": r"C:\Users\ArcXN\AppData\Local\AnthropicClaude\Claude.exe"},
    {"name": "Visual Studio", "exe": r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"},
]


def monitor_apps():
    """Check which known apps are installed."""
    findings = []
    available = []
    for app in KNOWN_APPS:
        exists = Path(app["exe"]).exists()
        available.append({"name": app["name"], "path": app["exe"], "installed": exists})
        if not exists:
            findings.append({
                "type": "app_missing", "severity": "info",
                "title": f"{app['name']} not installed",
                "description": app["exe"],
                "risk_score": 0.1, "roi_score": 0.5,
            })

    installed_count = sum(1 for a in available if a["installed"])
    return {
        "monitor": "apps",
        "status": "ok",
        "snapshot": {
            "total": len(available),
            "installed": installed_count,
            "missing": len(available) - installed_count,
            "apps": available,
        },
        "findings": findings,
    }


# ---------------------------------------------------------------------------
# All monitors
# ---------------------------------------------------------------------------
ALL_MONITORS = {
    "telemetry": monitor_telemetry,
    "services": monitor_services,
    "processes": monitor_processes,
    "network": monitor_network,
    "reboot": monitor_reboot,
    "apps": monitor_apps,
}


def run_all_monitors():
    """Run every monitor and return combined results."""
    results = {}
    all_findings = []
    for name, func in ALL_MONITORS.items():
        try:
            result = func()
            results[name] = result
            all_findings.extend(result.get("findings", []))
        except Exception as exc:
            results[name] = {"monitor": name, "status": "error", "error": str(exc), "findings": []}

    return results, all_findings