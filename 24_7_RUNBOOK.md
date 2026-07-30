
# ONENESS SYSTEM — 24/7 RUNBOOK
## From Zero to Always-On Operation

---

## PHASE 0: PREREQUISITES

Before the system can run 24/7, complete these steps:

- [ ] Python 3.11+ installed.
- [ ] `git` installed.
- [ ] `docker` installed (for later containerized deploy).
- [ ] Polymarket account created + funded with USDC on Polygon.
- [ ] Polygon wallet private key + funder address stored in `.env`.
- [ ] Claude API key stored in `.env` as `ANTHROPIC_API_KEY`.
- [ ] Discord webhook created and stored in `.env` as `DISCORD_WEBHOOK`.
- [ ] Optional: Kalshi account (for cross-platform arb).

---

## PHASE 1: INSTALL DEPENDENCIES

```bash
cd C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem
python -m venv venv
venv\Scripts\activate
pip install pyyaml python-dotenv pandas numpy py-clob-client websockets httpx eth-account docx2txt PyPDF2
```

Clone supporting repos into a `vendor/` folder:
```bash
git clone https://github.com/caiovicentino/polymarket-mcp-server.git vendor/polymarket-mcp-server
git clone https://github.com/ChadThackray/vol-delta-2023.git vendor/vol-delta-2023
```

---

## PHASE 2: CONFIGURE SECRETS

Create `.env` in the project root:

```ini
DEMO_MODE=true
POLYMARKET_PRIVATE_KEY=0x...
POLYMARKET_FUNDER_ADDRESS=0x...
ANTHROPIC_API_KEY=sk-ant-...
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

**Never commit `.env`.**

---

## PHASE 3: RUN THE ORCHESTRATOR (DEMO)

```bash
venv\Scripts\activate
python src/oneness_orchestrator.py --demo
```

You should see heartbeat logs for all 9 agents. In demo mode no real trades occur.

---

## PHASE 4: POPULATE MEMORY

1. Copy key documents into SecondBrain:
   - `C:\Users\ArcXN\OneDrive\Desktop\POLYMARKET-TRADING-BOT-SYSTEM-MASTER-BUILD-DOCUMENT-v1.0.docx`
   - `C:\Users\ArcXN\OneDrive\Desktop\PRO-X_Legal_Intelligence_Blueprint_Scroll02.docx`
   - `C:\Users\ArcXN\OneDrive\Desktop\rsb case\*`

2. OracleVault will ingest, summarize, and link them.

3. Verify `memory/vault/index.json` is populated.

---

## PHASE 5: BACKTEST ALL STRATEGIES

```bash
python deploy/run_backtest.py --strategy macd
python deploy/run_backtest.py --strategy rsi
python deploy/run_backtest.py --strategy cvd
```

Required metrics:
- Win rate > 55%
- Profit factor > 1.5
- Max drawdown < 20%
- Sharpe > 1.0
- ≥100 trades

If any fail, return to `config/agents.yaml` and recalibrate.

---

## PHASE 6: PAPER TRADING

Run for 7+ days in paper mode:

```bash
python src/oneness_orchestrator.py --paper
```

Check daily P&L in `memory/polymarket/pnl_daily.json`.
If paper P&L is negative, recalibrate.
If paper P&L matches backtest within 20%, proceed.

---

## PHASE 7: INCUBATION LADDER

Only when paper trading is profitable:

| Weeks | Trade Size |
|-------|-----------|
| 1–2   | $1        |
| 3–4   | $5        |
| 5–6   | $10       |
| 7–8   | $50       |
| 9+    | $100+     |

Set in `config/agents.yaml` → `risk.incubation_ladder`.

---

## PHASE 8: GO LIVE

1. Verify kill switch file works.
2. Verify Discord alerts fire.
3. Switch `DEMO_MODE=false` in `.env`.
4. Restart orchestrator.
5. Confirm first live trade via Discord alert.

---

## PHASE 9: CONTAINERIZE FOR 24/7

```bash
docker build -t oneness-system .
docker run -d --name oneness-system \
  --env-file .env \
  -v oneness-memory:/app/memory \
  --restart unless-stopped \
  oneness-system
```

For multi-agent scale:
```bash
docker run -d --name oneness-finance -e STACK=finance oneness-system
docker run -d --name oneness-legal -e STACK=legal oneness-system
docker run -d --name oneness-memory -e STACK=memory oneness-system
```

---

## DAILY CHECKLIST

- [ ] Review Sentinel daily briefing.
- [ ] Confirm no kill-switch or legal-hold flags.
- [ ] Check open positions and P&L.
- [ ] Verify CaseBlade deadlines for next 7 days.
- [ ] Review OracleVault new ingestions.

---

## EMERGENCY PROCEDURES

### Kill Switch
Activate immediately if drawdown approaches 10%, system misbehaves, or legal emergency arises:
```powershell
New-Item -Path "C:\tmp\polymarket_bot_kill" -ItemType File -Force
```
Or message Sentinel: `/kill`.

### Legal Hold
CaseBlade will raise `legal_hold=true` automatically. RiskWarden then reduces exposure 50%.

### Recovery
1. Stop orchestrator.
2. Investigate logs in `memory/logs/`.
3. Fix issue.
4. Clear kill switch (`Remove-Item C:\tmp\polymarket_bot_kill`).
5. Restart.

---

## OPERATING NORMS

- Start every day in DEMO_MODE until you trust the new configuration.
- Never increase trade size faster than the incubation ladder.
- Never file legal documents without human review.
- Keep `.env` and private keys offline from version control.

---

*End of 24/7 Runbook*
