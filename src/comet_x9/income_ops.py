"""income_ops.py — Comet X9 passive-income playbook scout.
Scores the curated income-playbook library against local context and
returns the top-ranked plays ready for execution.
"""
import argparse
import json
import os
import shutil
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent.parent
PLAYBOOKS_PATH = SCRIPT_DIR / "lib" / "income_playbooks.json"

def load_playbooks():
    if not PLAYBOOKS_PATH.exists():
        return []
    data = json.loads(PLAYBOOKS_PATH.read_text(encoding="utf-8"))
    return data.get("playbooks", [])

def get_context():
    ctx = {
        "has_admin": False,
        "disk_free_percent": 0,
        "cpu_load": 0,
        "ram_free_gb": 0,
        "ai_apps_count": 0,
        "docker_available": bool(shutil.which("docker")),
        "dotnet_available": bool(shutil.which("dotnet")),
        "python_available": True,
        "has_github": bool(shutil.which("gh")),
        "has_node": bool(shutil.which("node")),
        "one_drive_active": False,
    }
    try:
        import ctypes
        ctx["has_admin"] = bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        pass
    try:
        import psutil
        disk = psutil.disk_usage(str(ROOT))
        ctx["disk_free_percent"] = round(disk.free / disk.total * 100, 2)
        ctx["cpu_load"] = psutil.cpu_percent(interval=0.5)
        ctx["ram_free_gb"] = round(psutil.virtual_memory().available / (1024**3), 2)
    except Exception:
        pass
    try:
        app_path = ROOT / "memory" / "aura" / "latest.json"
        if app_path.exists():
            data = json.loads(app_path.read_text(encoding="utf-8"))
            ctx["ai_apps_count"] = len(data.get("apps", []))
    except Exception:
        pass
    ctx["one_drive_active"] = any(p.name().lower() == "onedrive.exe" for p in __import__("psutil").process_iter(["name"])) if __import__("psutil", fromlist=["process_iter"]) else False
    return ctx

def score_playbook(pb, ctx):
    score = pb.get("annual_usd", 0) / 5000.0  # income value
    score += pb.get("passivity", 0.5) * 10     # prefer passive
    score -= pb.get("capital", 0) / 5000.0     # penalize capital need
    score -= pb.get("time", 10) / 5.0          # penalize time
    score -= pb.get("effort", "medium") == "high" and 3 or 0
    score += pb.get("skill", "medium") == "low" and 2 or 0

    # context boosts
    if pb["category"] == "ai_services" and ctx["ai_apps_count"] >= 3:
        score += 4
    if pb["category"] == "saas" and ctx["dotnet_available"]:
        score += 3
    if pb["category"] == "content" and ctx["ai_apps_count"] >= 2:
        score += 3
    if pb["category"] == "finance" and ctx["disk_free_percent"] > 10:
        score += 2
    if "real_estate" in pb["tags"] and (Path.home() / "OneDrive" / "Desktop" / "OnenessSystem" / "cases" / "rsb_nordskog").exists():
        score += 2  # user has foreclosure/real estate context
    if not ctx["has_admin"] and pb.get("capital", 0) > 10000:
        score -= 3  # avoid high-capital plays without admin/elevation context
    if ctx["ram_free_gb"] < 4:
        score -= 2  # system under pressure
    return round(score, 2)

def collect(out_path):
    playbooks = load_playbooks()
    ctx = get_context()
    scored = []
    for pb in playbooks:
        pb["score"] = score_playbook(pb, ctx)
        scored.append(pb)
    scored.sort(key=lambda x: x["score"], reverse=True)
    top = scored[:10]

    findings = []
    for i, pb in enumerate(top):
        findings.append({
            "type": "income_play",
            "source": "income_ops",
            "title": f"#{i+1}: {pb['name']}",
            "description": pb["one_liner"],
            "risk_score": 0.1,
            "roi_score": pb["score"],
            "data": pb,
        })

    total_annual = sum(p["annual_usd"] for p in top)
    avg_passivity = round(sum(p["passivity"] for p in top) / len(top), 2) if top else 0

    result = {
        "agent": "income_ops",
        "status": "ok",
        "count": len(findings),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "telemetry": {
            "playbooks_evaluated": len(playbooks),
            "top_10_annual_usd": total_annual,
            "avg_passivity": avg_passivity,
            "context": ctx,
        },
        "findings": findings,
        "top_plays": top,
    }
    Path(out_path).write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"status": "ok", "wrote": out_path, "count": len(findings), "top_annual_usd": total_annual}))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    collect(args.out)

if __name__ == "__main__":
    main()
