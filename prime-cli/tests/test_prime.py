"""Smoke tests for prime CLI."""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRIME = str(shutil.which("prime") or ROOT / "venv" / "Scripts" / "prime.exe")
if not Path(PRIME).exists():
    PRIME = str(ROOT.parent / "venv" / "Scripts" / "prime.exe")

def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [PRIME] + args,
        capture_output=True,
        text=True,
        cwd=ROOT,
    )


def test_help():
    r = run(["--help"])
    assert r.returncode == 0, r.stderr
    assert "Prime Fire Council" in r.stdout


def test_version():
    r = run(["--version"])
    assert r.returncode == 0, r.stderr
    assert "prime" in r.stdout


def test_doctor_json():
    r = run(["--json", "doctor"])
    assert r.returncode == 0, r.stderr
    data = r.stdout
    assert '"checks"' in data
    assert '"ready"' in data


def test_agents_list_json():
    r = run(["agents", "list", "--json"])
    assert r.returncode == 0, r.stderr
    assert '"id"' in r.stdout


def test_review_self():
    r = run(["review", "src", "--json"])
    assert r.returncode == 0, r.stderr
    assert '"target"' in r.stdout
