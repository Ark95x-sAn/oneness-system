"""Paper-trading Polymarket bot - demo mode only.

No real orders are placed. The bot reads signals, sizes via Kelly/EV,
and logs intended trades to memory/polymarket/paper_trades.json.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get("ONENESS_SYSTEM_ROOT", r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"))
MEMORY = ROOT / "memory" / "polymarket"
MEMORY.mkdir(parents=True, exist_ok=True)

from polymarket.risk.sizing import RiskEngine
from polymarket.signals.confluence import ConfluenceEngine

class PaperBot:
    def __init__(self, bankroll: float = 1000.0):
        self.bankroll = bankroll
        self.risk = RiskEngine(max_order_usd=50.0, max_exposure_usd=200.0, demo_mode=True)
        self.confluence = ConfluenceEngine()

    def evaluate(self, market_slug: str, probability: float, market_price: float):
        signals = self.confluence.example()
        conf = self.confluence.score(signals)
        sizing = self.risk.size(probability, market_price, self.bankroll)
        trade = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "market": market_slug,
            "model_probability": probability,
            "market_price": market_price,
            "direction": conf["direction"],
            "confluence_score": conf["score"],
            "edge": sizing.edge,
            "half_kelly_fraction": sizing.half_kelly_fraction,
            "suggested_usd": sizing.suggested_usd,
            "approved": sizing.approved,
            "demo_mode": self.risk.demo_mode,
            "signals": [{"source": s.source, "side": s.side, "strength": s.strength, "reason": s.reason} for s in signals],
        }
        self._log_trade(trade)
        return trade

    def _log_trade(self, trade: dict):
        path = MEMORY / "paper_trades.json"
        trades = []
        if path.exists():
            try:
                trades = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                trades = []
        trades.append(trade)
        path.write_text(json.dumps(trades, indent=2), encoding="utf-8")

if __name__ == "__main__":
    bot = PaperBot(bankroll=1000.0)
    result = bot.evaluate(market_slug="will-fed-cut-rates-in-july", probability=0.62, market_price=0.55)
    print(json.dumps(result, indent=2))


def run_daily():
    bot = PaperBot(bankroll=1000.0)
    markets = [
        ('will-fed-cut-rates-in-july', 0.62, 0.55),
        ('will-bitcoin-hit-100k-in-2026', 0.48, 0.42),
        ('will-trump-run-in-2028', 0.71, 0.65),
    ]
    results = []
    for slug, prob, price in markets:
        try:
            result = bot.evaluate(slug, prob, price)
            results.append(result)
        except Exception as e:
            results.append({'market': slug, 'error': str(e)})
    summary = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'count': len(results),
        'demo_mode': True,
        'total_suggested_usd': sum(r.get('suggested_usd', 0) for r in results if 'error' not in r),
        'approved_trades': sum(1 for r in results if r.get('approved')),
        'results': results,
    }
    summary_path = MEMORY / 'daily_paper_summary.json'
    summaries = []
    if summary_path.exists():
        try:
            summaries = json.loads(summary_path.read_text(encoding='utf-8'))
        except Exception:
            summaries = []
    summaries.append(summary)
    summary_path.write_text(json.dumps(summaries, indent=2), encoding='utf-8')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == '--daily':
    run_daily()


def backtest(trades: list, bankroll: float = 1000.0):
    """Simple backtest: assume each trade resolves at model probability."""
    pnl = 0.0
    wins = 0
    losses = 0
    for t in trades:
        edge = t.get("edge", 0)
        size = min(t.get("suggested_usd", 0), 50.0)
        if edge <= 0 or size <= 0:
            continue
        expected = size * edge
        pnl += expected
        if expected > 0:
            wins += 1
        elif expected < 0:
            losses += 1
    return {
        "bankroll": bankroll,
        "trades": len(trades),
        "wins": wins,
        "losses": losses,
        "expected_pnl": round(pnl, 2),
        "roi_pct": round(pnl / bankroll * 100, 2) if bankroll else 0.0,
    }
