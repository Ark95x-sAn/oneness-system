
# Oneness System v1.0

A unified 24/7 operating system that merges:
- **Polymarket trading bots** (MACD, RSI, CVD strategies)
- **PRO-X legal intelligence** (ethical case support, evidence, narrative)
- **SecondBrain vault** (PARA knowledge management)
- **Live legal workflows** (starting with RSB v. Nordskog, EQCV018537)

## Quick Start

```bash
cd C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem
python -m venv venv
venv\Scripts\activate
pip install pyyaml python-dotenv pandas numpy py-clob-client websockets httpx eth-account docx2txt PyPDF2
python src/oneness_orchestrator.py --demo
```

## The 9 Agents

| Agent | Role |
|-------|------|
| **OracleVault** | File ingestion, SecondBrain sync, knowledge graph |
| **MarketScryer** | Polymarket scanner + cross-platform arb watcher |
| **SignalForge** | MACD, RSI+VWAP, CVD signal generation |
| **TradeWeaver** | Limit-order execution and position tracking |
| **RiskWarden** | Kelly sizing, drawdown, kill switch, exposure limits |
| **PRO-X** | Ethical legal-intelligence and narrative design |
| **CaseBlade** | Case deadlines, procedural strikes, legal holds |
| **Sentinel** | Monitoring, alerts, daily briefings, audit trail |
| **Synapse** | Orchestrator, confluence scoring, 24/7 scheduler |

## Key Documents

- `ARCHITECTURE.md` — full system blueprint
- `24_7_RUNBOOK.md` — operational checklist
- `agents/agent_01_oraclevault.md` … `agent_09_synapse.md` — per-agent specs
- `config/agents.yaml` — tunable configuration
- `src/oneness_orchestrator.py` — central scheduler scaffold

## Safety

- `DEMO_MODE=true` by default. No real trades until explicitly disabled.
- All legal outputs are labeled support materials, not legal advice.
- No impersonation of attorneys, officials, or court personnel.
- Kill switch and legal-hold integration reduce trading during legal emergencies.

## License / Use

Personal use system. Review all outputs before any financial, legal, or filing action.

