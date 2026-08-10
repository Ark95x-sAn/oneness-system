import json
"""ops_mind — Unified PC Operations Orchestration Mind.

A single brain that oversees all PC operations: health monitoring,
service tracking, process analysis, disk management, network diagnostics,
app inventory, and safe remediation generation.

Integrates with the existing Comet X9 and Net95X sub-agent layers while
providing a unified status report and continuous oversight loop.
"""
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
MEMORY = ROOT / "memory"
OPS_MIND_ROOT = MEMORY / "ops_mind"
RAW_DIR = OPS_MIND_ROOT / "raw"
REPORTS_DIR = OPS_MIND_ROOT / "reports"
REMEDIATIONS_DIR = OPS_MIND_ROOT / "remediations"
LOG_DIR = OPS_MIND_ROOT / "logs"
STATE_PATH = OPS_MIND_ROOT / "state.json"

# Monitor intervals (seconds)
DEFAULT_CYCLE_INTERVAL = 60
DEFAULT_REPORT_INTERVAL = 300
DEFAULT_REMEDIATE_INTERVAL = 600

# Health thresholds
CPU_CRITICAL = 90
CPU_HIGH = 70
RAM_CRITICAL = 90
RAM_HIGH = 80
DISK_LOW_PCT = 15
DISK_CRITICAL_PCT = 5

# Critical Windows services to watch
CRITICAL_SERVICES = [
    "wuauserv", "bits", "wscsvc", "WinDefend", "Spooler",
    "Dhcp", "Dnscache", "NlaSvc", "WSearch", "OnenessWeb",
    "gpsvc", "sppsvc", "MapsBroker",
]

def ensure_dirs():
    for d in (RAW_DIR, REPORTS_DIR, REMEDIATIONS_DIR, LOG_DIR):
        d.mkdir(parents=True, exist_ok=True)

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")

def load_json(path, default=None):
    import json
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return default