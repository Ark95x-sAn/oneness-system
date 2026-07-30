
"""Tests for agent module stubs."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.agents.oraclevault import OraclevaultAgent
from src.agents.marketscryer import MarketscryerAgent
from src.agents.signalforge import SignalforgeAgent
from src.agents.tradeweaver import TradeweaverAgent
from src.agents.riskwarden import RiskwardenAgent
from src.agents.prox import ProxAgent
from src.agents.caseblade import CasebladeAgent
from src.agents.sentinel import SentinelAgent


def test_agent_stubs_run():
    memory = Path("memory")
    agents = [
        OraclevaultAgent(memory),
        MarketscryerAgent(memory),
        SignalforgeAgent(memory),
        TradeweaverAgent(memory),
        RiskwardenAgent(memory),
        ProxAgent(memory),
        CasebladeAgent(memory),
        SentinelAgent(memory),
    ]
    for agent in agents:
        result = agent.tick()
        assert result["status"] == "ok"
        assert result["agent"] == agent.name
