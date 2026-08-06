"""Optional local HTTP API for the Sovereign Desktop dashboard."""
import json
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from .orchestrator import scan, launch
from .safety import preview

PORT = 9500


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode("utf-8"))

    def do_GET(self):
        if self.path == "/status":
            self._json(200, {"apps": scan()})
        elif self.path == "/apps":
            reg = json.loads((pathlib.Path(__file__).parent / "registry.json").read_text())
            self._json(200, reg)
        elif self.path == "/":
            self._json(200, {"service": "sovereign_desktop_api", "endpoints": ["/status", "/apps", "POST /launch/<app_id>"]})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path.startswith("/launch/"):
            app_id = self.path.split("/")[-1]
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8") if length else "{}"
            try:
                payload = json.loads(body)
            except Exception:
                payload = {}
            confirmed = payload.get("confirmed", False)
            if not confirmed:
                reg = json.loads((pathlib.Path(__file__).parent / "registry.json").read_text())
                cfg = reg["apps"].get(app_id, {})
                self._json(200, preview("launch", app_id, {
                    "launch_type": cfg.get("launch_type"),
                    "launch_value": cfg.get("launch_value")
                }))
                return
            result = launch(app_id, confirmed=True)
            self._json(200, result)
        else:
            self._json(404, {"error": "not found"})


def serve(port=PORT):
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"Sovereign Desktop API running at http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    serve()
