# ONENESS SYSTEM — MASTER INDEX

## Quick Start

```bat
cd C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem
scripts\run_prime_fire_council.bat
```

Then open: **http://localhost:5050**

---

## Core Documents

| Document | Purpose |
|----------|---------|
| `README.md` | Project overview |
| `ARCHITECTURE.md` | System blueprint |
| `24_7_RUNBOOK.md` | Install → backtest → paper → live → Docker |
| `INTEGRATIONS.md` | Claude/Blackbox/Copilot/OpenClaw/Codex/VS integration guide |
| `DEPLOYMENT_STATUS.md` | Current build/verify/fix status |
| `INDEX.md` | This file |

## Configuration

| File | Purpose |
|------|---------|
| `config/agents.yaml` | Agent schedules, risk limits, API endpoints |
| `config/prime_fire_council.json` | Top-level crew delegation config |
| `config/system_state.json` | Runtime agent health + risk state |

## Code

| Path | Purpose |
|------|---------|
| `src/oneness_orchestrator.py` | 24/7 Python orchestrator (Synapse) |
| `src/agents/*.py` | 9 agent module stubs |
| `src/Oneness.Web/` | ASP.NET Core AI serve control center |
| `tests/` | pytest suite |

## Operations

| Path | Purpose |
|------|---------|
| `scripts/health_check.py` | Deployment readiness checker |
| `scripts/run_demo.bat` | Run Python orchestrator demo |
| `scripts/run_prime_fire_council.bat` | Launch orchestrator + web app |
| `scripts/start_docker.bat` | Start Docker Desktop and wait |
| `scripts/integrations/*.ps1` | Launchers for Claude, OpenClaw, Codex, Copilot, Blackbox, Perplexity, VS scan/build |

## Memory Vault

| Path | Purpose |
|------|---------|
| `memory/vault/` | Mirrors SecondBrain structure |
| `memory/polymarket/` | Trading data |
| `memory/legal/cases/EQCV018537/` | RSB case seeded |
| `memory/logs/` | Logs, health checks, audit trail |

## The 9 Agents

1. **OracleVault** — memory ingestion
2. **MarketScryer** — market scanning
3. **SignalForge** — signal generation
4. **TradeWeaver** — order execution
5. **RiskWarden** — risk + kill switch
6. **PRO-X** — legal intelligence
7. **CaseBlade** — litigation workflow
8. **Sentinel** — monitoring + alerts
9. **Synapse** — orchestrator

---
*Prime Fire Council active when orchestrator + web app are running.*
