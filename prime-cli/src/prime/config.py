"""Configuration and environment loading for prime CLI."""
from __future__ import annotations

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path.home() / ".oneness" / ".env", override=False)
load_dotenv(Path(".env"), override=False)

DEFAULT_ROOT = Path.home() / "OneDrive" / "Desktop" / "OnenessSystem"
ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", DEFAULT_ROOT)).resolve()
WEB_URL = os.environ.get("ONENESS_WEB_URL", "http://localhost:5050")
VENV_PYTHON = ROOT / "venv" / "Scripts" / "python.exe"
ORCHESTRATOR = ROOT / "src" / "oneness_orchestrator.py"
RUN_SCRIPT = ROOT / "scripts" / "run_prime_fire_council.bat"
ADMIN_SCRIPT = ROOT / "scripts" / "integrations" / "RUN_AS_ADMIN_INSTALL.ps1"
AUTH_SCRIPT = ROOT / "scripts" / "fixers" / "run_all_auth.bat"
FIXER_SCRIPT = ROOT / "scripts" / "run_all_fixers.py"
CONFIG_YAML = ROOT / "config" / "agents.yaml"
MEMORY_LOGS = ROOT / "memory" / "logs"
