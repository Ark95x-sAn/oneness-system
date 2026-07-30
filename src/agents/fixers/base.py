"""Base class for problem-solving fixer agents."""
from dataclasses import dataclass, field
from pathlib import Path
from datetime import datetime, timezone
import json

@dataclass
class FixerResult:
    agent: str
    status: str = "unknown"
    findings: list[str] = field(default_factory=list)
    actions: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    recommendations: list[str] = field(default_factory=list)
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self):
        return {
            "agent": self.agent,
            "status": self.status,
            "findings": self.findings,
            "actions": self.actions,
            "errors": self.errors,
            "recommendations": self.recommendations,
            "timestamp": self.timestamp
        }

class FixerAgent:
    def __init__(self, memory_root: Path):
        self.memory = Path(memory_root)
        self.name = self.__class__.__name__
        self.result = FixerResult(agent=self.name)

    def run(self):
        raise NotImplementedError

    def log_action(self, msg: str):
        self.result.actions.append(msg)

    def log_finding(self, msg: str):
        self.result.findings.append(msg)

    def log_error(self, msg: str):
        self.result.errors.append(msg)

    def log_recommendation(self, msg: str):
        self.result.recommendations.append(msg)

    def save_result(self):
        out_dir = self.memory / "logs" / "fixers"
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f"{self.name}.json"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.result.to_dict(), f, indent=2)
        return path
