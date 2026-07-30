
#!/usr/bin/env python3
"""
Oneness System Orchestrator (SYNAPSE)
24/7 scheduler and confluence engine for 9-agent unified operation.
Safe-by-default: DEMO_MODE=true until explicitly disabled.

Run:
    python src/oneness_orchestrator.py --demo

This is a scaffold. Each agent's real logic can be swapped in as modules.
"""
import os
import sys
import json
import time
import logging
from dataclasses import dataclass, field
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

# Try to load YAML config; fallback to defaults
ROOT = Path(__file__).resolve().parent.parent
MEMORY = ROOT / "memory"
CONFIG = ROOT / "config"

try:
    import yaml
    with open(CONFIG / "agents.yaml", "r", encoding="utf-8") as f:
        CFG = yaml.safe_load(f)
except Exception as e:
    logging.warning("Could not load config/agents.yaml: %s. Using defaults.", e)
    CFG = {
        "system": {"demo_mode": True, "log_level": "INFO", "timezone": "America/Chicago"},
        "risk": {"max_order_size_usd": 50, "max_total_exposure_usd": 200, "max_drawdown_pct": 0.10},
        "confluence": {
            "signal_strength": 0.40, "risk_clearance": 0.30, "capital_availability": 0.15,
            "legal_clearance": 0.10, "human_approval": 0.05,
            "auto_execute_threshold": 0.80, "human_approval_threshold": 0.60,
            "legal_action_threshold": 0.95,
        },
        "schedule": {
            "oraclevault_sync": 60, "market_scan": 300, "signal_generate": 300,
            "risk_check": 60, "legal_check": 3600, "sentinel_heartbeat": 60,
        },
    }

DEMO_MODE = os.environ.get("DEMO_MODE", "true").lower() == "true" or CFG.get("system", {}).get("demo_mode", True)

logging.basicConfig(
    level=logging.getLevelName(CFG.get("system", {}).get("log_level", "INFO")),
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(MEMORY / "logs" / "orchestrator.log", mode="a"),
    ],
)
log = logging.getLogger("SYNAPSE")

# Ensure memory dirs exist
for sub in ["polymarket", "legal", "vault", "logs"]:
    (MEMORY / sub).mkdir(parents=True, exist_ok=True)


@dataclass
class Agent:
    name: str
    codename: str
    duties: List[str] = field(default_factory=list)
    last_heartbeat: Optional[str] = None
    healthy: bool = True


class OnenessOrchestrator:
    """Central scheduler, confluence scorer, and dispatch gate."""

    def __init__(self):
        self.agents: Dict[str, Agent] = {
            "ORACLEVAULT": Agent("OracleVault", "ORACLEVAULT", ["vault_sync", "ingest", "index"]),
            "MARKETSCRYER": Agent("MarketScryer", "MARKETSCRYER", ["market_scan", "arb_watch"]),
            "SIGNALFORGE": Agent("SignalForge", "SIGNALFORGE", ["macd", "rsi", "cvd", "new_market"]),
            "TRADEWEAVER": Agent("TradeWeaver", "TRADEWEAVER", ["order_place", "order_cancel", "position_sync"]),
            "RISKWARDEN": Agent("RiskWarden", "RISKWARDEN", ["sizing", "limits", "kill_switch", "drawdown"]),
            "PROX": Agent("PRO-X", "PROX", ["intake", "issue_spot", "evidence", "narrative", "simulation"]),
            "CASEBLADE": Agent("CaseBlade", "CASEBLADE", ["deadlines", "strikes", "timing", "legal_hold"]),
            "SENTINEL": Agent("Sentinel", "SENTINEL", ["heartbeat", "alerts", "daily_brief", "audit"]),
            "SYNAPSE": Agent("Synapse", "SYNAPSE", ["confluence", "dispatch", "schedule", "recalibration"]),
        }
        self.timers: Dict[str, float] = {}
        self.now = datetime.now(timezone.utc)
        self.risk_state = self._load_risk_state()
        log.info("=== ONENESS SYSTEM ORCHESTRATOR STARTED ===")
        log.info("DEMO_MODE=%s", DEMO_MODE)

    # ------------------------------------------------------------------
    # State persistence
    # ------------------------------------------------------------------
    def _load_risk_state(self) -> dict:
        path = MEMORY / "risk_state.json"
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        return {
            "kill_switch_active": False,
            "legal_hold": False,
            "daily_drawdown_pct": 0.0,
            "total_exposure_usd": 0.0,
            "available_capital_usd": 0.0,
            "reserve_usd": 0.0,
            "max_order_usd": CFG["risk"]["max_order_size_usd"],
            "max_exposure_usd": CFG["risk"]["max_total_exposure_usd"],
            "demo_mode": DEMO_MODE,
            "last_updated": self.now.isoformat(),
        }

    def _save_risk_state(self):
        self.risk_state["last_updated"] = datetime.now(timezone.utc).isoformat()
        with open(MEMORY / "risk_state.json", "w", encoding="utf-8") as f:
            json.dump(self.risk_state, f, indent=2)

    def _save_system_state(self):
        state = {
            "system": "OnenessSystem",
            "version": "1.0",
            "demo_mode": DEMO_MODE,
            "agents": {
                codename: {
                    "healthy": agent.healthy,
                    "last_heartbeat": agent.last_heartbeat,
                    "duties": agent.duties,
                }
                for codename, agent in self.agents.items()
            },
            "risk_state": self.risk_state,
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }
        with open(CONFIG / "system_state.json", "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)

    def _audit(self, event: str, payload: dict):
        audit_path = MEMORY / "logs" / "audit_trail.json"
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "agent": "SYNAPSE",
            "event": event,
            "payload": payload,
        }
        try:
            data = []
            if audit_path.exists():
                with open(audit_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            data.append(entry)
            with open(audit_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            log.error("Audit write failed: %s", e)

    # ------------------------------------------------------------------
    # Agent tick stubs
    # ------------------------------------------------------------------
    def tick_oraclevault(self):
        """Stub: in production, watch vault changes and ingest."""
        log.info("ORACLEVAULT sync tick")
        self._heartbeat("ORACLEVAULT")

    def tick_marketscryer(self):
        """Stub: in production, call Gamma API."""
        log.info("MARKETSCRYER scan tick")
        watchlist_path = MEMORY / "polymarket" / "watchlist.json"
        sample = {
            "scanned_at": datetime.now(timezone.utc).isoformat(),
            "markets": [],
            "note": "stub output — replace with real Gamma API call",
        }
        with open(watchlist_path, "w", encoding="utf-8") as f:
            json.dump(sample, f, indent=2)
        self._heartbeat("MARKETSCRYER")

    def tick_signalforge(self):
        """Stub: in production, run strategies on watchlist."""
        log.info("SIGNALFORGE strategy tick")
        signals_path = MEMORY / "polymarket" / "signals.json"
        sample = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "signals": [],
            "note": "stub output — replace with real strategy code",
        }
        with open(signals_path, "w", encoding="utf-8") as f:
            json.dump(sample, f, indent=2)
        self._heartbeat("SIGNALFORGE")

    def tick_tradeweaver(self):
        """Stub: in production, execute cleared signals."""
        log.info("TRADEWEAVER execution tick")
        self._heartbeat("TRADEWEAVER")

    def tick_riskwarden(self):
        """Stub: in production, update risk state from positions."""
        log.info("RISKWARDEN risk check tick")
        self.risk_state["last_updated"] = datetime.now(timezone.utc).isoformat()
        self._save_risk_state()
        self._heartbeat("RISKWARDEN")

    def tick_prox(self):
        """Stub: in production, review intakes and build legal materials."""
        log.info("PRO-X legal review tick")
        self._heartbeat("PROX")

    def tick_caseblade(self):
        """Stub: in production, check deadlines and update strike plan."""
        log.info("CASEBLADE case workflow tick")
        self._heartbeat("CASEBLADE")

    def tick_sentinel(self):
        """Stub: in production, send heartbeat and check all agents."""
        log.info("SENTINEL heartbeat tick")
        for codename, agent in self.agents.items():
            if not agent.healthy:
                log.warning("Agent %s is marked unhealthy", codename)
        self._heartbeat("SENTINEL")

    # ------------------------------------------------------------------
    # Confluence engine
    # ------------------------------------------------------------------
    def confluence_score(self, signal: dict) -> float:
        """Compute 0-100 confluence score for a trading signal."""
        w = CFG["confluence"]
        signal_strength = signal.get("strength", 0.0)
        risk_clearance = 1.0 if not self.risk_state.get("kill_switch_active") and not self.risk_state.get("legal_hold") else 0.0
        capital = min(1.0, self.risk_state.get("available_capital_usd", 0) / max(1.0, CFG["risk"]["max_total_exposure_usd"]))
        legal_clearance = 0.0 if self.risk_state.get("legal_hold") else 1.0
        human_approval = 1.0 if signal.get("human_approved") else 0.0

        score = (
            w["signal_strength"] * signal_strength +
            w["risk_clearance"] * risk_clearance +
            w["capital_availability"] * capital +
            w["legal_clearance"] * legal_clearance +
            w["human_approval"] * human_approval
        ) * 100
        return round(score, 2)

    def dispatch(self, signal: dict):
        """Decide whether to execute, queue, or suppress a signal."""
        score = self.confluence_score(signal)
        threshold_auto = CFG["confluence"]["auto_execute_threshold"] * 100
        threshold_queue = CFG["confluence"]["human_approval_threshold"] * 100

        decision = None
        if score >= threshold_auto:
            if DEMO_MODE:
                decision = "PAPER_EXECUTE"
            else:
                decision = "LIVE_EXECUTE"
        elif score >= threshold_queue:
            decision = "HUMAN_QUEUE"
        else:
            decision = "SUPPRESS"

        log.info("DISPATCH signal=%s score=%s decision=%s", signal.get("id", "?"), score, decision)
        self._audit("dispatch", {"signal": signal, "score": score, "decision": decision})
        return decision

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _heartbeat(self, codename: str):
        agent = self.agents[codename]
        agent.last_heartbeat = datetime.now(timezone.utc).isoformat()
        agent.healthy = True

    def _due(self, key: str, interval_seconds: int) -> bool:
        now = time.time()
        if key not in self.timers or now - self.timers[key] >= interval_seconds:
            self.timers[key] = now
            return True
        return False

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------
    def run(self):
        log.info("Entering 24/7 loop. Press Ctrl+C to stop.")
        try:
            while True:
                sched = CFG["schedule"]
                if self._due("oraclevault", sched.get("oraclevault_sync", 60)):
                    self.tick_oraclevault()
                if self._due("marketscryer", sched.get("market_scan", 300)):
                    self.tick_marketscryer()
                if self._due("signalforge", sched.get("signal_generate", 300)):
                    self.tick_signalforge()
                if self._due("tradeweaver", sched.get("signal_generate", 300)):
                    self.tick_tradeweaver()
                if self._due("riskwarden", sched.get("risk_check", 60)):
                    self.tick_riskwarden()
                if self._due("prox", sched.get("legal_check", 3600)):
                    self.tick_prox()
                if self._due("caseblade", sched.get("legal_check", 3600)):
                    self.tick_caseblade()
                if self._due("sentinel", sched.get("sentinel_heartbeat", 60)):
                    self.tick_sentinel()

                self._save_system_state()
                time.sleep(1)
        except KeyboardInterrupt:
            log.info("Shutdown requested. Saving state...")
            self._save_system_state()
            log.info("State saved. Goodbye.")


if __name__ == "__main__":
    orch = OnenessOrchestrator()
    # Example confluence test
    test_signal = {"id": "test-1", "strength": 0.85, "human_approved": False, "side": "BUY"}
    orch.dispatch(test_signal)
    orch.run()
