# MOONPAY CLI — WINDOWS BLOCKER NOTE
## Date: 2026-07-30

### Issue
`@moonpay/cli` installs successfully, but at runtime it fails to load:
`@open-wallet-standard/core-win32-x64-msvc`

### Root cause
The `@open-wallet-standard/core` package only ships a Linux binary (`bin/ows`).
No Windows native prebuild is present in the installed package.

### Implications
- MoonPay CLI cannot run natively on this Windows PC as installed.
- Likely supported paths:
  1. MoonPay Agents desktop app (Windows version)
  2. WSL2 / Linux environment
  3. Wait for official Windows support

### Recommended next step
Use the MoonPay Agents desktop app for Windows or sign up at https://www.moonpay.com/agents and complete KYC there.
