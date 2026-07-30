
# ONENESS SYSTEM v1.0
## Unified 24/7 Operating Architecture
### Trading Intelligence × Legal Intelligence × SecondBrain Memory

**Classification:** Master Build Document  
**Created:** 2026-07-28  
**Vault Root:** `C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem`  
**SecondBrain Vault:** `C:\Users\ArcXN\OneDrive\Desktop\SecondBrain`  
**Status:** Build-ready — all 9 agents specified, orchestrator scaffolded, safe-by-default (DEMO_MODE=true).

---

## 1. PURPOSE

The Oneness System merges three existing intelligence layers into one autonomous, always-on command layer:

| Layer | Source Document | Function |
|-------|----------------|----------|
| **Polymarket Trading Bot** | `POLYMARKET-TRADING-BOT-SYSTEM-MASTER-BUILD-DOCUMENT-v1.0.docx` | Generate alpha, execute trades, manage risk |
| **PRO-X Legal Intelligence** | `PRO-X_Legal_Intelligence_Blueprint_Scroll02.docx` | Translate facts into court-ready structure, ethical legal support |
| **SecondBrain Vault** | `C:\Users\ArcXN\OneDrive\Desktop\SecondBrain` | Persistent memory, PARA organization, sync, knowledge graph |
| **Live Case (RSB v. Nordskog)** | `C:\Users\ArcXN\OneDrive\Desktop\rsb case` | First operational legal workflow — foreclosure defense |

**Oneness = one shared memory, one risk posture, one orchestrator, nine specialist agents.**

---

## 2. CORE DESIGN PRINCIPLES

1. **Single Source of Truth** — all agents read/write through the `memory/` tree and the SecondBrain vault.
2. **Safe-by-Default** — `DEMO_MODE=true` until every agent passes its checklist.
3. **Human-in-the-Loop** — execution above $50, legal filings, and wallet actions require approval.
4. **Ethical Hard Boundaries** — no impersonation, no fabricated evidence, no unauthorized access, no market manipulation.
5. **24/7 Loop** — 5-minute trading loop, hourly legal/case checks, continuous vault sync.
6. **Confluence Before Action** — no single agent trades or files alone; signals and legal moves are scored by the orchestrator.

---

## 3. SYSTEM LAYERS

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER / HUMAN                            │
│  Approves high-risk moves, reviews daily briefings, sets goals   │
└───────────────────────┬─────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────────┐
│                    AGENT 09 — SYNAPSE                            │
│  Orchestrator · Confluence Engine · Scheduler · Kill-Switch Gate  │
└───────────────────────┬─────────────────────────────────────────┘
                        │
    ┌───────────────────┼───────────────────┐
    ▼                   ▼                   ▼
┌─────────┐      ┌──────────┐      ┌─────────────┐
│ FINANCE │      │  LEGAL   │      │   MEMORY    │
│  STACK  │      │  STACK   │      │   STACK     │
└────┬────┘      └────┬─────┘      └──────┬──────┘
     │                │                    │
 ┌───▼───┐      ┌────▼────┐          ┌────▼─────┐
 │Market │      │ PRO-X   │          │ ORACLE   │
 │Scryer │      │ Legal   │          │ Vault    │
 │(Agent2)│     │ Intel   │          │ (Agent1) │
 └───┬───┘      │(Agent6) │          └────┬─────┘
     │          └────┬────┘               │
 ┌───▼───┐      ┌────▼────┐          ┌────▼─────┐
 │Signal │      │ CASE    │          │ SENTINEL │
 │Forge  │      │ Blade   │          │ Monitor  │
 │(Agent3)│     │(Agent7) │          │(Agent8)  │
 └───┬───┘      └────┬────┘          └────┬─────┘
     │               │                     │
 ┌───▼───┐     ┌────▼────┐                │
 │Trade  │     │         │                │
 │Weaver │     │         │                │
 │(Agent4)│    │         │                │
 └───┬───┘     │         │                │
     │         │         │                │
 ┌───▼───┐     │         │                │
 │Risk   │     │         │                │
 │Warden │     │         │                │
 │(Agent5)│    │         │                │
 └───┬───┘     │         │                │
     └─────────┴─────────┴────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────────┐
│                    SHARED MEMORY TREE                            │
│  /memory/polymarket  /memory/legal  /memory/vault  /memory/logs│
│  + SecondBrain sync to OneDrive                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. THE NINE AGENTS (x9)

| # | Agent | Codename | Stack | Core Function | Loop Cadence |
|---|-------|----------|-------|---------------|--------------|
| 1 | **OracleVault** | `ORACLEVAULT` | Memory | Ingest, tag, summarize, sync all files into SecondBrain + Oneness memory | Continuous (file watcher) |
| 2 | **MarketScryer** | `MARKETSCRYER` | Finance | Scan Polymarket/Gamma API for tradeable markets and cross-platform arb | 5 minutes |
| 3 | **SignalForge** | `SIGNALFORGE` | Finance | Run MACD(3/15/3), RSI+VWAP, CVD divergence; emit scored signals | 5 minutes |
| 4 | **TradeWeaver** | `TRADEWEAVER` | Finance | Place/cancel limit orders, track positions and P&L | On signal |
| 5 | **RiskWarden** | `RISKWARDEN` | Finance | Enforce Kelly sizing, exposure, drawdown, kill switch, rate limits | Every tick + hourly |
| 6 | **PRO-X** | `PROX` | Legal | Intake translator, issue spotter, evidence architect, humanized narrative | On intake + daily |
| 7 | **CaseBlade** | `CASEBLADE` | Legal | Deadline tracking, procedural strikes, service/mediation/standing analysis | Hourly |
| 8 | **Sentinel** | `SENTINEL` | Memory | Health checks, logs, Discord/Telegram alerts, daily P&L/case briefings | Continuous |
| 9 | **Synapse** | `SYNAPSE` | Orchestrator | Confluence scoring, dispatch, cross-agent coordination, 24/7 scheduler | 60 seconds |

---

## 5. SHARED MEMORY SCHEMA

```
OnenessSystem/
├── memory/
│   ├── vault/               # Mirrors SecondBrain structure
│   │   ├── 0-Inbox/
│   │   ├── 1-Projects/
│   │   ├── 2-Areas/
│   │   ├── 3-Resources/
│   │   └── 5-Zettelkasten/
│   ├── polymarket/
│   │   ├── watchlist.json   # Markets being tracked
│   │   ├── signals.json     # Latest signals from all strategies
│   │   ├── positions.json   # Open positions
│   │   ├── orders.json      # Open orders
│   │   └── pnl_daily.json   # Daily summaries
│   ├── legal/
│   │   ├── cases/
│   │   │   └── EQCV018537/
│   │   │       ├── timeline.json
│   │   │       ├── evidence_matrix.json
│   │   │       ├── deadlines.json
│   │   │       ├── strike_plan.json
│   │   │       └── narrative.md
│   │   └── intake/          # New legal intakes
│   └── logs/
│       ├── agent_logs/      # One log per agent
│       ├── alerts.json      # Alert history
│       └── audit_trail.json # Every decision, every action
```

---

## 6. CONFLUENCE SCORING (SYNAPSE)

No agent acts alone. Synapse computes a **Confluence Score (0-100)**:

| Component | Weight | Source |
|-----------|--------|--------|
| Signal strength (MarketScryer + SignalForge) | 40% | `signals.json` |
| Risk clearance (RiskWarden) | 30% | Risk API / kill-switch state |
| Capital availability | 15% | `positions.json` + wallet balance |
| Legal/case posture clearance | 10% | CaseBlade flags (e.g., active foreclosure deadlines = no big risk) |
| Human pre-approval | 5% | Confirmation flag for trades >$50 |

**Execution thresholds:**
- **≥ 80:** Auto-execute (if DEMO_MODE=false and below $50)
- **60-79:** Queue for human approval
- **< 60:** Suppress

For legal actions, the threshold is **95** and always requires human review.

---

## 7. RISK CIRCUIT

The RiskWarden maintains a **System Risk State**:

```json
{
  "kill_switch_active": false,
  "daily_drawdown_pct": 0.0,
  "total_exposure_usd": 0.0,
  "max_exposure_usd": 200,
  "max_order_usd": 50,
  "max_trades_per_hour": 20,
  "reserve_pct": 0.10,
  "demo_mode": true,
  "legal_hold": false,
  "last_updated": "2026-07-28T22:00:00Z"
}
```

Any agent can set `legal_hold=true` (e.g., CaseBlade detects an emergency filing deadline). When true, RiskWarden reduces max exposure by 50% and pauses non-critical trading.

---

## 8. 24/7 OPERATING LOOP

```
Minute 0-4   → OracleVault syncs vault changes
Minute 5     → MarketScryer scans; SignalForge runs strategies
Minute 6     → Synapse scores confluence
Minute 7     → RiskWarden validates; TradeWeaver executes approved trades
Minute 8     → Sentinel logs + alerts
Hourly       → CaseBlade checks legal deadlines; PRO-X reviews new intakes
Daily 00:00  → Sentinel generates P&L + legal briefing; OracleVault archives
Weekly       → Synapse runs recalibration review
```

---

## 9. ETHICAL & SAFETY BOUNDARIES

- No market manipulation, wash trading, or spoofing.
- No impersonation of attorneys, clerks, judges, or officials.
- No fabrication or alteration of evidence.
- No unauthorized access to accounts, court systems, or databases.
- All legal outputs labeled as **support materials, not legal advice**.
- Trading starts in DEMO_MODE and scales through incubation ($1 → $5 → $10 → $50).

---

## 10. NEXT ACTIONS

1. Review all 9 agent specification files in `agents/`.
2. Configure `config/agents.yaml` with real API keys (keep `.env` local, never commit).
3. Run `src/oneness_orchestrator.py` in DEMO_MODE.
4. Complete the 24/7 Runbook checklist before going live.
5. Update `SecondBrain/7-Orchestration/THIS-NODE.md` to point here.

---

*End of Architecture Document*
