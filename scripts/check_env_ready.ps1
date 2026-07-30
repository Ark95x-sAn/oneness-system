# API Key Quick-Setup Helper for Oneness System
# Run this after pasting real keys into .env
param(
    [switch]$Auto,
    [switch]$OpenEnv
)

$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
cd $root

if ($OpenEnv) {
    notepad "$root\.env"
    return
}

function Test-Key($name) {
    $val = [Environment]::GetEnvironmentVariable($name, "Process")
    if (-not $val) { $val = (Get-Content "$root\.env" | Where-Object { $_ -match "^$name=" }) -split "=" | Select-Object -Skip 1 | Join-String }
    return ($val -and ($val -notmatch "your-(openai|anthropic|perplexity|blackbox)-key"))
}

$keys = @{}
@("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "PERPLEXITY_API_KEY", "BLACKBOX_API_KEY") | ForEach-Object {
    $keys[$_] = Test-Key $_
}

Write-Host "`n.env key status:" -ForegroundColor Cyan
$keys.GetEnumerator() | ForEach-Object {
    $color = if ($_.Value) { "Green" } else { "Yellow" }
    Write-Host "  $($_.Key): $([bool]$_.Value)" -ForegroundColor $color
}

$ready = $keys["OPENAI_API_KEY"] -and $keys["ANTHROPIC_API_KEY"]
if ($ready) {
    Write-Host "`n✅ .env looks ready. Run next:" -ForegroundColor Green
    Write-Host "  .\venv\Scripts\prime.exe auth" -ForegroundColor Cyan
    if ($Auto) {
        .\venv\Scripts\prime.exe auth
    }
} else {
    Write-Host "`n⚠️  At minimum, paste real OPENAI_API_KEY and ANTHROPIC_API_KEY into .env first." -ForegroundColor Yellow
}
