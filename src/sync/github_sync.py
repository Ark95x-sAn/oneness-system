"""GitHub Sync Engine — keep Oneness System code + memory backed up to a private repo."""
from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", r"C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem"))
SYNC_LOG = ROOT / "memory" / "logs" / "github_sync.json"
REPO_NAME = os.environ.get("ONENESS_REPO", "oneness-system")
REMOTE_URL = os.environ.get("ONENESS_REMOTE", f"https://github.com/{os.environ.get('GITHUB_USER', 'user')}/{REPO_NAME}.git")


def _run(cmd: list[str], cwd: Path | None = None) -> dict[str, Any]:
    try:
        r = subprocess.run(cmd, cwd=cwd or ROOT, capture_output=True, text=True, timeout=60, check=False)
        return {"ok": r.returncode == 0, "returncode": r.returncode, "stdout": r.stdout.strip(), "stderr": r.stderr.strip()}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def _git_init() -> dict[str, Any]:
    git_dir = ROOT / ".git"
    if not git_dir.exists():
        return _run(["git", "init"])
    return {"ok": True, "note": "git already initialized"}


def _git_remote() -> dict[str, Any]:
    remotes = _run(["git", "remote", "-v"])
    if REMOTE_URL.split("/")[-2].replace("https://github.com/", "") not in remotes.get("stdout", ""):
        return _run(["git", "remote", "add", "origin", REMOTE_URL])
    return {"ok": True, "note": "remote already set"}


def _auth_check() -> dict[str, Any]:
    r = _run(["gh", "auth", "status"])
    return {"authenticated": r["ok"], "details": r}


def sync(commit_message: str | None = None) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    msg = commit_message or f"sync: {now}"
    results = {
        "timestamp": now,
        "init": _git_init(),
        "remote": _git_remote(),
        "auth": _auth_check(),
    }

    if not results["auth"]["authenticated"]:
        results["status"] = "auth_required"
        results["next_step"] = "Run 'gh auth login' or set GH_TOKEN, then re-run sync."
        _log(results)
        return results

    # Stage and commit
    results["add"] = _run(["git", "add", "."])
    results["commit"] = _run(["git", "commit", "-m", msg])
    results["push"] = _run(["git", "push", "-u", "origin", "main"])
    results["status"] = "synced" if results["push"]["ok"] else "push_failed"
    _log(results)
    return results


def _log(results: dict[str, Any]) -> None:
    SYNC_LOG.parent.mkdir(parents=True, exist_ok=True)
    entries = []
    if SYNC_LOG.exists():
        try:
            entries = json.loads(SYNC_LOG.read_text(encoding="utf-8"))
        except Exception:
            entries = []
    entries.append(results)
    SYNC_LOG.write_text(json.dumps(entries[-50:], indent=2), encoding="utf-8")


if __name__ == "__main__":
    import sys
    commit = sys.argv[1] if len(sys.argv) > 1 else None
    print(json.dumps(sync(commit), indent=2, default=str))
