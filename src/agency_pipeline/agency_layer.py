"""agency_layer.py — Dispatch any registered agent by ID.

The registry maps 100+ agent IDs to worker scripts/commands with default args.
This is the pass-down layer: a single chat instruction selects a blueprint,
which dispatches to coordinators, which dispatch to registered agents.
"""
import json
import subprocess
from pathlib import Path
from typing import Dict, Any, List

ROOT = Path(__file__).resolve().parent.parent.parent
REGISTRY_PATH = ROOT / "src" / "agency_pipeline" / "agency_registry.json"


def load_registry() -> Dict[str, Any]:
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def list_agents(domain: str = None) -> List[Dict[str, Any]]:
    reg = load_registry()
    agents = reg.get("agents", [])
    if domain:
        agents = [a for a in agents if a.get("domain") == domain]
    return agents


def dispatch(agent_id: str, confirmed: bool = False, extra_args: List[str] = None) -> Dict[str, Any]:
    reg = load_registry()
    agent = next((a for a in reg.get("agents", []) if a["id"] == agent_id), None)
    if not agent:
        return {"ok": False, "error": f"agent {agent_id} not found"}

    if agent.get("requires_confirmation") and not confirmed:
        return {
            "ok": False,
            "status": "preview",
            "agent_id": agent_id,
            "display": agent.get("display"),
            "description": agent.get("description"),
            "message": f"Agent '{agent_id}' requires confirmation. Pass confirmed=True to execute.",
        }

    worker = ROOT / agent["worker"]
    if not worker.exists():
        return {"ok": False, "error": f"worker not found: {worker}"}

    args = ["python", str(worker), *agent.get("args", [])]
    if extra_args:
        args.extend(extra_args)

    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
            cwd=str(ROOT),
        )
        stdout = result.stdout.strip()[-2000:] if result.stdout else ""
        stderr = result.stderr.strip()[-1000:] if result.stderr else ""
        return {
            "ok": result.returncode == 0,
            "agent_id": agent_id,
            "command": " ".join(args),
            "stdout": stdout,
            "stderr": stderr,
            "returncode": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "agent_id": agent_id, "error": "timeout after 300s"}
    except Exception as exc:
        return {"ok": False, "agent_id": agent_id, "error": str(exc)}


def dispatch_domain(domain: str, confirmed: bool = False, limit: int = None) -> List[Dict[str, Any]]:
    agents = list_agents(domain)
    if limit:
        agents = agents[:limit]
    return [dispatch(a["id"], confirmed=confirmed) for a in agents]


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--domain")
    parser.add_argument("--dispatch")
    parser.add_argument("--confirmed", action="store_true")
    args = parser.parse_args()
    if args.list:
        agents = list_agents(args.domain)
        print(json.dumps({"count": len(agents), "agents": agents}, indent=2))
    elif args.dispatch:
        print(json.dumps(dispatch(args.dispatch, confirmed=args.confirmed), indent=2))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
