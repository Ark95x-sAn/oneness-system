"""Risk engine: Kelly/EV sizing for prediction-market positions."""
from __future__ import annotations
import json
from dataclasses import dataclass
from pathlib import Path

@dataclass
class SizingResult:
    edge: float
    kelly_fraction: float
    half_kelly_fraction: float
    suggested_usd: float
    max_usd: float
    approved: bool

class RiskEngine:
    def __init__(self, max_order_usd: float = 50.0, max_exposure_usd: float = 200.0, demo_mode: bool = True):
        self.max_order_usd = max_order_usd
        self.max_exposure_usd = max_exposure_usd
        self.demo_mode = demo_mode

    def size(self, probability: float, market_price: float, bankroll: float = 1000.0):
        edge = probability - market_price
        if edge <= 0 or market_price <= 0 or market_price >= 1:
            return SizingResult(edge=edge, kelly_fraction=0.0, half_kelly_fraction=0.0, suggested_usd=0.0, max_usd=0.0, approved=False)
        win_p = probability
        loss_p = 1 - probability
        b = (1 - market_price) / market_price
        kelly = (win_p * b - loss_p) / b if b > 0 else 0.0
        half_kelly = kelly / 2
        suggested = min(bankroll * half_kelly, self.max_order_usd)
        total_exposure = min(bankroll * half_kelly, self.max_exposure_usd)
        approved = suggested > 0 and not self.demo_mode
        return SizingResult(edge=edge, kelly_fraction=kelly, half_kelly_fraction=half_kelly, suggested_usd=suggested, max_usd=total_exposure, approved=approved)

    def can_trade(self, signal_score: float):
        return signal_score >= 0.65 and not self.demo_mode

    def load_state(self):
        path = Path(r"C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\memory\risk_state.json")
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
        return {"kill_switch_active": False, "legal_hold": False, "daily_drawdown_pct": 0.0, "total_exposure_usd": 0.0, "available_capital_usd": 0.0, "demo_mode": True}
