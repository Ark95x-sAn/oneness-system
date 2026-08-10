# Operations Mind — Unified PC Operations Oversight

The Operations Mind is a single orchestration brain that oversees all PC
operations: health monitoring, service tracking, process analysis, disk
management, network diagnostics, app inventory, and safe remediation
generation.

## Architecture

```
src/ops_mind/
  __init__.py       Module init, paths, constants, thresholds
  monitors.py       6 health monitors (telemetry, services, processes, network, reboot, apps)
  mind.py           Core orchestration loop + CLI
  reporter.py       Unified status report generator with recommendations
  remediator.py     Safe, preview-only remediation script generator
```

## Quick Start

```bat
cd C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem

REM Single cycle + report + remediations
scripts\run_ops_mind.bat --once

REM Quick health check
scripts\run_ops_mind.bat --health

REM Current status (no new cycle)
scripts\run_ops_mind.bat --status

REM Continuous 24/7 oversight loop
scripts\run_ops_mind.bat --loop
```

## Commands

| Command | Description |
|---------|-------------|
| `--once` | Run a full cycle, generate report + remediations, then exit |
| `--cycle` | Run a single monitoring cycle |
| `--report` | Generate a status report from the last cycle |
| `--remediate` | Generate remediation scripts from current findings |
| `--health` | Quick health check (single cycle, summary only) |
| `--status` | Show current saved state (no new cycle) |
| `--loop` | Run continuous 24/7 oversight loop |

## Monitors

| Monitor | What it checks |
|---------|---------------|
| **telemetry** | CPU %, RAM %, disk free space |
| **services** | 13 critical Windows services (WinDefend, DHCP, DNS, etc.) |
| **processes** | Top 15 CPU/memory processes, flags WSL/OneDrive hogs |
| **network** | Connectivity to Google DNS, GitHub, Google Web + DNS resolution |
| **reboot** | Pending reboot detection (CBS, WindowsUpdate, PendingFileRename) |
| **apps** | Known app inventory (Chrome, Codex CLI, Notion, Docker, etc.) |

## Health Score

0-100 scale (100 = perfectly healthy):
- Each critical finding: -20 points
- Each warning: -8 points
- Each info: -2 points
- Additional metric-based adjustments for CPU/RAM/disk/reboot

| Score | Status |
|-------|--------|
| 85+ | EXCELLENT |
| 70-84 | GOOD |
| 50-69 | FAIR |
| 30-49 | POOR |
| 0-29 | CRITICAL |

## Output Locations

| Path | Contents |
|------|----------|
| `memory/ops_mind/raw/` | Per-cycle raw JSON data |
| `memory/ops_mind/reports/` | Unified status reports (latest = `latest-report.json`) |
| `memory/ops_mind/remediations/` | Preview-only .ps1 remediation scripts |
| `memory/ops_mind/logs/` | Operations Mind log file |
| `memory/ops_mind/state.json` | Current state (cycles run, health score, findings) |

## Install as Scheduled Task

Runs a monitoring cycle every 5 minutes in the background:

```powershell
.\scripts\install_ops_mind_service.ps1
```

Remove:
```powershell
.\scripts\install_ops_mind_service.ps1 -Remove
```

## Safety

- **All monitors are read-only** — they collect state without modifying anything.
- **All remediation scripts are PREVIEW ONLY** — they are written to disk but never executed.
- **The user must review and explicitly run** each remediation script.
- No process kills, service starts, disk cleanup, or reboots happen automatically.
- Per AGENTS.md: all destructive actions require explicit user approval.