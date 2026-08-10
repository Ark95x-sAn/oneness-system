"""remediator.py — Safe, preview-only remediation script generator.

Generates .ps1 remediation scripts for identified issues. All scripts are
PREVIEW ONLY — they are written to disk but NEVER executed automatically.
The user must review and explicitly run each script.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from . import REMEDIATIONS_DIR, now_iso, write_json


# Templates for safe remediation scripts
REMEDIATION_TEMPLATES = {
    "cpu_critical": {
        "filename": "cpu_reduce_pressure",
        "script": [
            "# REMEDIATION: Reduce CPU pressure",
            "# REVIEW BEFORE RUNNING — this script is preview-only",
            "# This script identifies and optionally stops high-CPU processes",
            "",
            "Write-Host '=== CPU Pressure Remediation ==='",
            "Write-Host 'Current top CPU consumers:'",
            "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{N='CPU_s';E={[math]::Round($_.CPU,1)}}, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize",
            "",
            "Write-Host ''",
            "Write-Host 'To stop a process (replace PID): Stop-Process -Id <PID> -Force'",
            "Write-Host 'To shut down WSL: wsl --shutdown'",
            "Write-Host 'Review which processes are safe to stop before proceeding.'",
        ],
    },
    "ram_critical": {
        "filename": "ram_reduce_pressure",
        "script": [
            "# REMEDIATION: Reduce RAM pressure",
            "# REVIEW BEFORE RUNNING — this script is preview-only",
            "",
            "Write-Host '=== RAM Pressure Remediation ==='",
            "Write-Host 'Current memory usage:'",
            "$os = Get-CimInstance Win32_OperatingSystem",
            "$ramPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)",
            "Write-Host \"RAM: $ramPct% used\"",
            "",
            "Write-Host ''",
            "Write-Host 'Top memory consumers:'",
            "Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, Id, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize",
            "Write-Host 'Close unnecessary applications or browser tabs to free RAM.'",
        ],
    },
    "disk_low": {
        "filename": "disk_cleanup",
        "script": [
            "# REMEDIATION: Disk cleanup",
            "# REVIEW BEFORE RUNNING — this script modifies files",
            "# Run disk-cleanup-helper.ps1 to reclaim temp/scratch files",
            "",
            "Write-Host '=== Disk Cleanup Remediation ==='",
            "$disk = Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\"",
            "$freeGB = [math]::Round($disk.FreeSpace/1GB, 1)",
            "Write-Host \"Current free space: $freeGB GB\"",
            "",
            "Write-Host ''",
            "Write-Host 'To reclaim temp files (requires approval):'",
            "Write-Host '  .\\disk-cleanup-helper.ps1 -Reclaim'",
            "Write-Host ''",
            "Write-Host 'To run Windows Disk Cleanup:'",
            "Write-Host '  cleanmgr /sagerun:1'",
        ],
    },
    "services_stopped": {
        "filename": "services_restart",
        "script": [
            "# REMEDIATION: Restart stopped critical services",
            "# REVIEW BEFORE RUNNING — this script starts Windows services",
            "",
            "Write-Host '=== Service Remediation ==='",
            "Write-Host 'Stopped critical services (review before starting):'",
            "",
        ],
    },
    "reboot_pending": {
        "filename": "system_reboot",
        "script": [
            "# REMEDIATION: System reboot required",
            "# REVIEW BEFORE RUNNING — this will restart the computer",
            "# Save all work before proceeding!",
            "",
            "Write-Host '=== Reboot Remediation ==='",
            "Write-Host 'A system reboot is pending to complete Windows updates.'",
            "Write-Host 'Save all work, then run:'",
            "Write-Host '  shutdown /r /t 30  # 30-second countdown'",
            "Write-Host 'Or cancel with: shutdown /a'",
        ],
    },
    "network_unreachable": {
        "filename": "network_repair",
        "script": [
            "# REMEDIATION: Network connectivity repair",
            "# REVIEW BEFORE RUNNING — this resets network components",
            "",
            "Write-Host '=== Network Remediation ==='",
            "Write-Host 'Flushing DNS cache...'",
            "ipconfig /flushdns",
            "Write-Host ''",
            "Write-Host 'To reset network adapter (requires admin):'",
            "Write-Host '  netsh winsock reset'",
            "Write-Host '  netsh int ip reset'",
            "Write-Host '  ipconfig /release; ipconfig /renew'",
        ],
    },
    "dns_failure": {
        "filename": "dns_repair",
        "script": [
            "# REMEDIATION: DNS repair",
            "# REVIEW BEFORE RUNNING — restarts DNS service",
            "",
            "Write-Host '=== DNS Remediation ==='",
            "Write-Host 'Flushing DNS cache...'",
            "ipconfig /flushdns",
            "Write-Host ''",
            "Write-Host 'To restart DNS client (requires admin):'",
            "Write-Host '  Restart-Service -Name Dnscache -Force'",
        ],
    },
}


def generate_remediations(findings, remediations_dir=None):
    """Generate preview-only remediation scripts for all findings."""
    remediations_dir = remediations_dir or REMEDIATIONS_DIR
    remediations_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    generated = []
    seen_types = set()

    for finding in findings:
        ftype = finding.get("type", "")
        template = REMEDIATION_TEMPLATES.get(ftype)

        if template and ftype not in seen_types:
            seen_types.add(ftype)
            lines = list(template["script"])

            # Add service-specific info for services_stopped
            if ftype == "services_stopped":
                stopped = finding.get("stopped_services", [])
                for svc in stopped:
                    lines.append(f"Write-Host '  {svc}: Start-Service -Name {svc} (check if safe first)'")
                lines.append("Write-Host ''")
                lines.append("Write-Host 'Start services individually after review:'")
                for svc in stopped:
                    lines.append(f"# Start-Service -Name '{svc}'")

            # Add finding context
            lines.append("")
            lines.append(f"# Finding: {finding.get('title', ftype)}")
            lines.append(f"# Severity: {finding.get('severity', 'unknown')}")
            lines.append(f"# Risk score: {finding.get('risk_score', 0)}")
            lines.append(f"# Generated: {ts}")

            # Write script
            safe_name = template["filename"]
            script_name = f"{ts}_{safe_name}.ps1"
            script_path = remediations_dir / script_name

            script_content = "\r\n".join(lines)
            script_path.write_text(script_content, encoding="utf-8")

            generated.append({
                "finding_type": ftype,
                "script_path": str(script_path),
                "script_name": script_name,
                "severity": finding.get("severity"),
                "title": finding.get("title"),
                "preview_only": True,
            })

    result = {
        "generated_at": now_iso(),
        "total_generated": len(generated),
        "generated": generated,
        "note": "All scripts are PREVIEW ONLY. Review and run manually with explicit approval.",
    }

    # Save manifest
    manifest_path = remediations_dir / "latest-remediations.json"
    write_json(manifest_path, result)

    return result