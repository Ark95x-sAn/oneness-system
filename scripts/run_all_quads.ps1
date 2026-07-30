# RUN ALL 4 QUADS
# Executes the four highest-leverage compounding actions.

param(
    [switch]$SkipGate1UserActions
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
cd $root

Write-Host "`n=== QUAD 1: PUBLISH CONTENT BUNDLE ===" -ForegroundColor Cyan
.\scripts\publish_content_bundle.ps1

Write-Host "`n=== QUAD 2: START QDRANT / FALLBACK INDEXER ===" -ForegroundColor Cyan
.\scripts\start_qdrant_and_index.ps1 -UseFallback

Write-Host "`n=== QUAD 3: GATE 1 DEFEAT CHECKLIST ===" -ForegroundColor Cyan
if ($SkipGate1UserActions) {
    Write-Host "Skipped (user will run admin install / .env / restart manually)" -ForegroundColor Yellow
} else {
    .\scripts\defeat_gate1_checklist.ps1
}

Write-Host "`n=== QUAD 4: SCAFFOLD PAPER-TRADING BOT ===" -ForegroundColor Cyan
$env:PYTHONPATH = "$root\src"
.\venv\Scripts\python.exe -m polymarket.paper_bot | .\venv\Scripts\python.exe -m json.tool

Write-Host "`n=== ALL QUADS COMPLETE ===" -ForegroundColor Green
Write-Host "Artifacts:" -ForegroundColor Cyan
Write-Host "  - publish/README.md, publish/DROPS_DIGEST.md, publish/BLOG_POST.md" -ForegroundColor Gray
Write-Host "  - memory/qdrant_fallback/index.json" -ForegroundColor Gray
Write-Host "  - memory/logs/gate1_check.json" -ForegroundColor Gray
Write-Host "  - memory/polymarket/paper_trades.json" -ForegroundColor Gray
