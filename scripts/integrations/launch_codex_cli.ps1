# Launch OpenAI Codex CLI in target directory
param([string]$Directory = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem")
Push-Location $Directory

# Find the installed codex CLI (fallback through common paths)
$codexPath = $null
if (Test-Path "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe") {
    $codexPath = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" | Sort-Object FullName -Descending | Select-Object -First 1
} elseif (Get-Command codex -ErrorAction SilentlyContinue) {
    $codexPath = (Get-Command codex).Source
}

if ($null -eq $codexPath -or -not (Test-Path $codexPath)) {
    Write-Error "Codex CLI not found. Install via: npm install -g @openai/codex"
    Pop-Location
    exit 1
}

Write-Host "Launching Codex from: $codexPath" -ForegroundColor Green
& $codexPath

Pop-Location
