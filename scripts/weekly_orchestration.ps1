# Oneness Weekly Orchestration
# Runs once per week. Refreshes content bundle and runs all quads in background.

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

Step "Publish Content Bundle" ".\scripts\publish_content_bundle.ps1"
Step "Run All Quads" ".\scripts\run_all_quads.ps1 -SkipGate1UserActions"
Step "Property Re-score" "`$env:PYTHONPATH = '$root\src'; .\venv\Scripts\python.exe .\scripts\rescore_property_ops.py"

$logPath = "$root\memory\logs\weekly_orchestration.json"
$logs = @()
if (Test-Path $logPath) { $logs = Get-Content $logPath -Raw | ConvertFrom-Json }
$logs += $log
$logs | ConvertTo-Json -Depth 4 | Set-Content $logPath -Encoding utf8

Write-Host "`nWeekly orchestration complete. Log: $logPath" -ForegroundColor Green
