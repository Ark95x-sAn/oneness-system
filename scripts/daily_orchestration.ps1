# Oneness Daily Orchestration — Passive AI Wealth Generation
# Runs every day. Safe: demo mode only, no real money spent.

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
cd $root

$log = @{timestamp=(Get-Date -Format "o"); steps=@()}
function Step($name, $cmd) {
    Write-Host "[$name]" -ForegroundColor Cyan
    try {
        $output = Invoke-Expression $cmd 2>&1 | Out-String
        $log.steps += @{name=$name; status="ok"; output=$output.Substring(0, [Math]::Min(500, $output.Length))}
    } catch {
        $log.steps += @{name=$name; status="error"; output=$_.ToString()}
    }
}

Step "PC Admin Pass" ".\scripts\pc_admin_pass.ps1"
Step "Aura Start" ".\venv\Scripts\prime.exe aura start"
Step "852 Pulse + Signature" ".\venv\Scripts\prime.exe 852 --intent rise --json; .\venv\Scripts\python.exe -m src.intelligence.pattern_signature"
Step "Network-95 Cycle" "python `"$env:USERPROFILE\.codex\skills\network-95-division\scripts\orchestrate.py`" --cycle"
Step "Memory Index Refresh" ".\scripts\start_qdrant_and_index.ps1 -UseFallback"
Step "Paper Bot Demo" "`$env:PYTHONPATH = '$root\src'; .\venv\Scripts\python.exe -m polymarket.paper_bot --daily"

$logPath = "$root\memory\logs\daily_orchestration.json"
$logs = @()
if (Test-Path $logPath) { $logs = Get-Content $logPath -Raw | ConvertFrom-Json }
$logs += $log
$logs | ConvertTo-Json -Depth 4 | Set-Content $logPath -Encoding utf8

Write-Host "`nDaily orchestration complete. Log: $logPath" -ForegroundColor Green
