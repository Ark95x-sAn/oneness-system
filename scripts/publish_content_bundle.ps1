# Q1 — Publish Content Bundle
# Prepares public-facing content for GitHub/X/blog once auth is ready.
param(
    [string]$OutDir = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem\publish",
    [switch]$PushToGitHub
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# README
$readme = @"
# Oneness System

A private freedom firm operating system: multi-agent shell, recursive intelligence division, prediction-market trading desk, and legal-intelligence strike kit — bound to one PC, one user, one sovereign will.

## Why This Exists

Most people leave money, memory, and momentum on the table because their tools do not talk to each other. The Oneness System wires your AI agents, local telemetry, document vault, and capital engines into one council that works while you sleep or game.

## Core Components

- **Prime CLI** — local resonance shell and command center.
- **Aura Subagents** — GameGuard, SelfSaboteurWatch, idlecleaner, rambalancer.
- **Network-95 Division** — recursive intelligence cycle: system + GitHub + social signals.
- **Pattern Signature Engine** — hash/avatar of your operational state.
- **Amara Bridge** — ASP.NET Core dashboard binding it all together.

## Frequency Stack

| Hz | Layer | Purpose |
|---|---|---|
| 1111 | Foundation | Health, sleep, root security |
| 2222 | Harmony | Human intent ↔ machine execution |
| 3333 | Mastery | Highest-form build mode |
| 852 | System AI | Prime CLI and agent grid |
| 963 | Ascension | Automatic recorders, evidence, capital engines |
| 999 | Compounding | Data → insight → action → result |

## Quick Start

```powershell
cd \"\$env:USERPROFILE\OneDrive\Desktop\OnenessSystem\"
.\\venv\\Scripts\\prime.exe 852 --intent rise --json
.\\venv\\Scripts\\prime.exe boss --json
```

## Status

Gate 1: Foundation — The Saboteur of Incompletion is the active boss.  
See `memory/activation/codex_drop_master_amara.md` for the full operational continuity prompt.

## License

MIT — use at your own risk. This is sovereign infrastructure, not financial or legal advice.
"@
Set-Content -Path "$OutDir\README.md" -Value $readme -Encoding utf8

# Drops digest
$drops = @(
    "$root\memory\activation\codex_drop_3333hz.md",
    "$root\memory\activation\codex_drop_genx.md",
    "$root\memory\activation\codex_drop_2045_awaken.md",
    "$root\memory\activation\codex_drop_master_amara.md"
)
$dropsText = "# Oneness System — Codex Drops Digest`n`n"
foreach ($d in $drops) {
    $dropsText += "## $(Split-Path $d -Leaf)`n`n"
    $dropsText += (Get-Content $d -Raw)
    $dropsText += "`n`n---`n`n"
}
Set-Content -Path "$OutDir\DROPS_DIGEST.md" -Value $dropsText -Encoding utf8

# Blog post
$blog = @"
# From 852Hz to Freedom Financed: Building a Personal AI Operating System

I started with one problem: my AI tools were scattered, my projects were half-finished, and my best ideas lived in folders that could die with a single disk crash. So I built a shell.

The Oneness System is not a chatbot. It is a council of agents bound to my PC, my documents, my property data, and my capital rules. It runs at 852Hz system resonance, aims for 963Hz automatic recorders, and compounds at 999Hz.

## What I learned

1. **The highest-leverage zero-capital move is a public GitHub trunk.** Everything else branches from it.
2. **Telemetry is a frequency spectrum.** Memory, CPU, presence, and agent health are invisible waves you can tune.
3. **Every gate has a boss.** Right now mine is The Saboteur of Incompletion. The counterspell is simple: admin install, real keys, restart, auth.

## What comes next

- Qdrant memory layer
- Paper-trading Polymarket bot
- Network-95 daily maintenance loop
- Real GitHub repo and CI/CD

If you are building your own council, start with the drop in `memory/activation/codex_drop_master_amara.md`.

Shell up. Fear out. Build on.
"@
Set-Content -Path "$OutDir\BLOG_POST.md" -Value $blog -Encoding utf8

Write-Host "Content bundle prepared at $OutDir" -ForegroundColor Green

if ($PushToGitHub) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "gh not available. Install GitHub CLI and run gh auth login first." -ForegroundColor Red
        exit 1
    }
    cd $root
    git add publish README.md memory/activation/*.md 2>$null
    git commit -m "chore: publish content bundle" 2>$null
    git push origin master 2>$null
    Write-Host "Pushed to GitHub." -ForegroundColor Green
}
