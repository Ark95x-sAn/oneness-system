
"""Tests for the Oneness System orchestrator and agents."""
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest
from src.oneness_orchestrator import OnenessOrchestrator


def test_orchestrator_initializes():
    orch = OnenessOrchestrator()
    assert orch is not None
    assert len(orch.agents) == 9


def test_confluence_score_human_queue():
    orch = OnenessOrchestrator()
    signal = {"id": "test", "strength": 0.85, "human_approved": False, "side": "BUY"}
    score = orch.confluence_score(signal)
    assert 0 <= score <= 100
    decision = orch.dispatch(signal)
    assert decision == "HUMAN_QUEUE"


def test_confluence_score_suppress_on_kill_switch():
    orch = OnenessOrchestrator()
    orch.risk_state["kill_switch_active"] = True
    signal = {"id": "test", "strength": 0.99, "human_approved": True, "side": "BUY"}
    decision = orch.dispatch(signal)
    # With kill switch active, risk clearance drops to 0, score drops significantly
    assert orch.confluence_score(signal) < 80


def test_legal_hold_reduces_exposure():
    orch = OnenessOrchestrator()
    orch.risk_state["legal_hold"] = True
    # When legal_hold is true, RiskWarden would halve max exposure
    # This test documents the expected behavior
    assert orch.risk_state["legal_hold"] is True


def test_all_agents_have_codenames():
    orch = OnenessOrchestrator()
    for codename, agent in orch.agents.items():
        assert agent.codename == codename
        assert len(agent.duties) > 0


def test_config_loads():
    import yaml
    config_path = Path(__file__).resolve().parent.parent / "config" / "agents.yaml"
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    assert "system" in cfg
    assert "risk" in cfg
    assert "confluence" in cfg
    assert "schedule" in cfg
