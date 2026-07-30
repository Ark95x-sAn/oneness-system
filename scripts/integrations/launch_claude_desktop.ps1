# Launch Claude Desktop app
$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { $claude = "C:\Users\ArcXN\AppData\Local\Microsoft\WinGet\Links\claude.exe" }
if (Test-Path $claude) {
    Start-Process -FilePath $claude -ArgumentList @("--show-main-window") -WindowStyle Normal
    Write-Host "Claude Desktop launched"
} else { Write-Error "Claude executable not found" }
