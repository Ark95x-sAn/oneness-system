# INTEL BRIEF — MoonPay Agents / MoonAgents
## Identified: 2026-07-30 via autonomous browser recon
## Source: https://support.moonpay.com/en/articles/586487-moonagents-fund-your-ai

### What it is
MoonPay Agents (MoonAgents) is a non-custodial software layer that gives AI agents access to 54 crypto-specific tools across 17 key skills. It lets AI agents manage wallets, execute trades, and transact autonomously on your behalf through the MoonPay Agents desktop app or MoonPay CLI (`mp`).

### Why it matches the user's description
- Funding: bank payments (US, EU, GBP), Apple Pay, Venmo, PayPal
- Chains: Bitcoin, Ethereum, Solana, Base, Polygon, Arbitrum, Optimism, BNB, Avalanche, TRON
- Keys: stored on device using OS keychain encryption (non-custodial)
- AI surfaces: Claude, ChatGPT/Codex, Gemini, Grok
- CLI install: `npm install -g @moonpay/cli`

### Key capabilities
1. moonpay-auth
2. moonpay-block-explorer
3. moonpay-buy-crypto
4. moonpay-check-wallet
5. moonpay-deposit
6. moonpay-discover-tokens
7. moonpay-export-data
8. moonpay-feedback
9. moonpay-fund-polymarket
10. moonpay-mcp
11. moonpay-missions
12. moonpay-price-alerts
13. moonpay-swap-tokens
14. moonpay-trading-automation
15. moonpay-upgrade
16. moonpay-virtual-account
17. moonpay-x402

### Critical note
KYC required before agent can execute fiat onramps/virtual-account transactions.

### Integration fit with Oneness System
- Connects directly to Polymarket paper/live bot (moonpay-fund-polymarket)
- Provides capital rails for the Capital Gate / Risk Phantom controls
- Can be wrapped as a Codex skill / MCP server (moonpay-mcp)
- Enables 24/7 agent treasury operations (x402, DCA, limit orders)

### Next actions
1. Install MoonPay CLI: `npm install -g @moonpay/cli`
2. Complete KYC and fund virtual account
3. Add `moonpay-mcp` to Oneness System MCP config
4. Wire TRADEWEAVER / ORACLEVAULT to MoonPay skills
5. Run first autonomous command via `mp` CLI
