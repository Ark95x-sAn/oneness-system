# Launch OpenClaw CLI or Companion
$openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
if ($openclaw) {
    Start-Process -FilePath openclaw -WindowStyle Normal
    Write-Host "OpenClaw launched"
} else {
    $companion = "C:\Users\ArcXN\OneDrive\Desktop\OpenClaw Companion.lnk"
    if (Test-Path $companion) {
        Start-Process -FilePath $companion
        Write-Host "OpenClaw Companion launched"
    } else { Write-Error "OpenClaw not found" }
}
