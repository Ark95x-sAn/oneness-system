"""Optional local HTTP API for the Sovereign Desktop dashboard."""
import json
import pathlib
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from .orchestrator import scan, launch
from .safety import preview

PORT = 9500


def _project_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent.parent


def _read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _run_pipeline(blueprint: str, confirmed: bool = False) -> dict:
    root = _project_root()
    cmd = ["python", str(root / "src" / "agency_pipeline" / "pipeline.py"), "--blueprint", blueprint, "--confirmed" if confirmed else ""]
    cmd = [c for c in cmd if c]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False, cwd=str(root))
        try:
            data = json.loads(result.stdout.splitlines()[-1])
        except Exception:
            data = {"stdout": result.stdout[-2000:], "stderr": result.stderr[-1000:]}
        data["ok"] = result.returncode == 0
        return data
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def _dispatch_agent(agent_id: str, confirmed: bool = False) -> dict:
    root = _project_root()
    cmd = ["python", str(root / "src" / "agency_pipeline" / "pipeline.py"), "--dispatch-agent", agent_id]
    if confirmed:
        cmd.append("--confirmed")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False, cwd=str(root))
        try:
            data = json.loads(result.stdout.splitlines()[-1])
        except Exception:
            data = {"stdout": result.stdout[-2000:], "stderr": result.stderr[-1000:]}
        data["ok"] = result.returncode == 0
        return data
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode("utf-8"))

    def do_OPTIONS(self):
        self._json(200, {})

    def do_GET(self):
        root = _project_root()
        if self.path == "/status":
            self._json(200, {"apps": scan()})
        elif self.path == "/apps":
            reg = _read_json(pathlib.Path(__file__).parent / "registry.json")
            self._json(200, reg)
        elif self.path == "/blueprints":
            self._json(200, _read_json(root / "memory" / "agency" / "blueprints_cache.json"))
        elif self.path == "/agents":
            domain = None
            if "?" in self.path:
                qs = self.path.split("?", 1)[1]
                for pair in qs.split("&"):
                    if "=" in pair:
                        k, v = pair.split("=", 1)
                        if k == "domain":
                            domain = v
            data = _read_json(root / "memory" / "agency" / "agents_cache.json")
            if domain and "agents" in data:
                data["agents"] = [a for a in data["agents"] if a.get("domain") == domain]
                data["count"] = len(data["agents"])
            self._json(200, data)
        elif self.path == "/":
            self._json(200, {
                "service": "sovereign_desktop_api",
                "endpoints": ["/status", "/apps", "/blueprints", "/agents", "POST /launch/<app_id>", "POST /pipeline/<blueprint>", "POST /agent/<agent_id>"]
            })
        else:
            self._json(404, {"error": "not found"})

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8") if length else "{}"
        try:
            return json.loads(body)
        except Exception:
            return {}

    def do_POST(self):
        if self.path.startswith("/launch/"):
            app_id = self.path.split("/")[-1]
            payload = self._read_body()
            confirmed = payload.get("confirmed", False)
            if not confirmed:
                reg = json.loads((pathlib.Path(__file__).parent / "registry.json").read_text())
                cfg = reg.get("apps", {}).get(app_id, {})
                self._json(200, preview("launch", app_id, {
                    "launch_type": cfg.get("launch_type"),
                    "launch_value": cfg.get("launch_value")
                }))
                return
            result = launch(app_id, confirmed=True)
            self._json(200, result)
        elif self.path.startswith("/pipeline/"):
            blueprint = self.path.split("/")[-1]
            payload = self._read_body()
            confirmed = payload.get("confirmed", False)
            if not confirmed:
                root = _project_root()
                result = subprocess.run(
                    ["python", str(root / "src" / "agency_pipeline" / "pipeline.py"), "--blueprint", blueprint],
                    capture_output=True, text=True, timeout=30, check=False, cwd=str(root)
                )
                try:
                    preview_data = json.loads(result.stdout.splitlines()[-1])
                except Exception:
                    preview_data = {"stdout": result.stdout[-1000:]}
                preview_data["status"] = "preview"
                self._json(200, preview_data)
                return
            self._json(200, _run_pipeline(blueprint, confirmed=True))
        elif self.path.startswith("/agent/"):
            agent_id = self.path.split("/")[-1]
            payload = self._read_body()
            confirmed = payload.get("confirmed", False)
            if not confirmed:
                root = _project_root()
                result = subprocess.run(
                    ["python", str(root / "src" / "agency_pipeline" / "pipeline.py"), "--dispatch-agent", agent_id],
                    capture_output=True, text=True, timeout=30, check=False, cwd=str(root)
                )
                try:
                    preview_data = json.loads(result.stdout.splitlines()[-1])
                except Exception:
                    preview_data = {"stdout": result.stdout[-1000:]}
                preview_data["status"] = "preview"
                self._json(200, preview_data)
                return
            self._json(200, _dispatch_agent(agent_id, confirmed=True))
        else:
            self._json(404, {"error": "not found"})


def serve(port=PORT):
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"Sovereign Desktop API running at http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    serve()
