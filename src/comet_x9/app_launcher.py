
"""app_launcher.py — AI app and connector launcher.

Discovers configured AI apps on the PC and reports launch readiness.
Does not store credentials; reads paths from known locations.
"""
import argparse
import json
from pathlib import Path
from datetime import datetime, timezone

KNOWN_APPS = [
    {"name": "Claude Desktop", "exe": r"C:\Users\ArcXN\AppData\Local\AnthropicClaude\Claude.exe", "args": ""},
    {"name": "Claude Code", "exe": r"C:\Users\ArcXN\AppData\Roaming\npm\claude-code.cmd", "args": ""},
    {"name": "Codex CLI", "exe": r"C:\Users\ArcXN\AppData\Roaming\npm\codex.cmd", "args": ""},
    {"name": "Google Chrome", "exe": r"C:\Program Files\Google\Chrome\Application\chrome.exe", "args": ""},
    {"name": "Notion", "exe": r"C:\Users\ArcXN\AppData\Local\Programs\Notion\Notion.exe", "args": ""},
    {"name": "Docker Desktop", "exe": r"C:\Program Files\Docker\Docker\Docker Desktop.exe", "args": ""},
    {"name": "Visual Studio", "exe": r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe", "args": ""},
]

def collect():
    findings = []
    available = []
    for app in KNOWN_APPS:
        exists = Path(app["exe"]).exists()
        available.append({"name": app["name"], "path": app["exe"], "exists": exists})
        if not exists:
            findings.append({
                "type": "app_missing",
                "source": "app_launcher",
                "title": f"{app['name']} not found at expected path",
                "description": app["exe"],
                "risk_score": 0.1,
                "roi_score": 1.0,
            })

    if available:
        findings.append({
            "type": "app_inventory",
            "source": "app_launcher",
            "title": f"{sum(1 for a in available if a['exists'])}/{len(available)} AI apps available",
            "description": json.dumps(available),
            "risk_score": 0.0,
            "roi_score": 2.0,
            "data": available,
        })

    return {
        "agent": "app_launcher",
        "status": "ok",
        "count": len(findings),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "telemetry": {
            "total_apps": len(available),
            "available_apps": sum(1 for a in available if a["exists"]),
        },
        "findings": findings,
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    result = collect()
    Path(args.out).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({"status": "ok", "wrote": args.out, "count": result["count"]}))

if __name__ == "__main__":
    main()
