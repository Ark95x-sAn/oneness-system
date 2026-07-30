param([string]$Mode = "demo")
$orch = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\src\oneness_orchestrator.py"
$python = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\venv\Scripts\python.exe"
if (-not (Test-Path $python)) { $python = "python" }
$env:DEMO_MODE = if ($Mode -eq "live") { "false" } else { "true" }
Start-Process -FilePath $python -ArgumentList $orch, "--$Mode" -WindowStyle Hidden -WorkingDirectory "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"
Write-Host "Prime Fire Council orchestrator started in $Mode mode"
