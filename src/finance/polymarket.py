"""Polymarket data connector."""
from __future__ import annotations

import json
import urllib.request
from pathlib import Path
from typing import Any
from datetime import datetime, timezone

CLOB_HOST = "https://clob.polymarket.com"
GAMMA_API = "https://gamma-api.polymarket.com/markets"
MEMORY_DIR = Path(__file__).resolve().parent.parent.parent / "memory" / "polymarket"

def _num(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def fetch_gamma_markets(limit: int = 50, volume_min: float = 10000.0, liquidity_min: float = 5000.0) -> list[dict[str, Any]]:
    """Fetch active Polymarket markets from Gamma API."""
    url = f"{GAMMA_API}?limit={limit}&active=true&closed=false"
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "Oneness-Prime/2045"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode())
    markets = data if isinstance(data, list) else data.get("markets", [])
    filtered = [
        m for m in markets
        if _num(m.get("volume24hr")) >= volume_min and _num(m.get("liquidity")) >= liquidity_min
    ]
    return sorted(filtered, key=lambda x: _num(x.get("volume24hr")), reverse=True)


def fetch_clob_orderbook(token_id: str) -> dict[str, Any]:
    """Fetch order book for a specific Polymarket token."""
    url = f"{CLOB_HOST}/book/{token_id}"
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "Oneness-Prime/2045"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def save_markets_snapshot(markets: list[dict[str, Any]], filename: str = "markets.json") -> Path:
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    path = MEMORY_DIR / filename
    snapshot = {"timestamp": datetime.now(timezone.utc).isoformat(), "count": len(markets), "markets": markets}
    path.write_text(json.dumps(snapshot, indent=2, default=str), encoding="utf-8")
    return path


def load_latest_snapshot(filename: str = "markets.json") -> dict[str, Any]:
    path = MEMORY_DIR / filename
    if not path.exists():
        return {"timestamp": None, "count": 0, "markets": []}
    return json.loads(path.read_text(encoding="utf-8"))


def top_opportunities(n: int = 10) -> list[dict[str, Any]]:
    """Return top liquid markets with key stats."""
    markets = fetch_gamma_markets(limit=100)
    opportunities = []
    for m in markets[:n]:
        opportunities.append({
            "id": m.get("id"),
            "question": m.get("question"),
            "volume24h": _num(m.get("volume24hr")),
            "liquidity": _num(m.get("liquidity")),
            "spread": round(abs(_num(m.get("bestBid")) - _num(m.get("bestAsk"))), 4),
            "bestBid": _num(m.get("bestBid")),
            "bestAsk": _num(m.get("bestAsk")),
            "category": m.get("category"),
        })
    return opportunities
