"""Signal confluence engine: combine MACD, RSI, CVD, and sentiment."""
from __future__ import annotations
from dataclasses import dataclass
from typing import List

@dataclass
class Signal:
    source: str
    side: str
    strength: float
    reason: str

class ConfluenceEngine:
    def __init__(self, sources: List[str] = None):
        self.sources = sources or ["macd", "rsi", "cvd", "sentiment"]

    def score(self, signals: List[Signal]):
        if not signals:
            return {"score": 0.0, "direction": "none", "confidence": 0.0}
        yes = [s for s in signals if s.side == "yes"]
        no = [s for s in signals if s.side == "no"]
        yes_score = sum(s.strength for s in yes) / len(self.sources)
        no_score = sum(s.strength for s in no) / len(self.sources)
        if yes_score > no_score:
            return {"score": yes_score, "direction": "yes", "confidence": min(1.0, yes_score)}
        return {"score": no_score, "direction": "no", "confidence": min(1.0, no_score)}

    def example(self):
        return [
            Signal("macd", "yes", 0.72, "MACD line crossed above signal"),
            Signal("rsi", "yes", 0.55, "RSI 58, room before overbought"),
            Signal("cvd", "no", 0.40, "CVD flattening on ask side"),
            Signal("sentiment", "yes", 0.68, "Social volume rising for Yes"),
        ]
