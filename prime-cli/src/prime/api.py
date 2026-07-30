"""Minimal Oneness.Web API client."""
from __future__ import annotations

import json
import urllib.request
from typing import Any
from . import config

class OnenessAPI:
    def __init__(self, base_url: str = config.WEB_URL, timeout: int = 10):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(self, method: str, path: str, payload: dict | None = None) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        data = json.dumps(payload).encode() if payload else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            raise RuntimeError(f"HTTP {e.code}: {body}") from e
        except Exception as e:
            raise RuntimeError(f"API unreachable: {e}") from e

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/api/health")

    def agents(self) -> list[dict[str, Any]]:
        return self._request("GET", "/api/agents")

    def tick(self, agent_id: str) -> dict[str, Any]:
        return self._request("POST", f"/api/agents/{agent_id}/tick")

    def tools(self) -> list[dict[str, Any]]:
        return self._request("GET", "/api/tools")

    def projects(self) -> list[dict[str, Any]]:
        return self._request("GET", "/api/projects")

    def scan_projects(self) -> dict[str, Any]:
        return self._request("POST", "/api/projects/scan")

    def build_project(self, path: str, configuration: str = "Release") -> dict[str, Any]:
        return self._request("POST", f"/api/projects/build?path={path}&config={configuration}")
