# Q3 — Defeat Gate 1 Boss Checklist
# The Saboteur of Incompletion. Run each step; this script verifies state.

$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
$checks = @{}

# Check 1: running as admin
$checks.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Check 2: Oneness Windows service installed
$checks.ServiceInstalled = Get-Service -Name "OnenessWeb" -ErrorAction SilentlyContinue | ForEach-Object { $_.Status -ne $null }

# Check 3: .env has real keys
$envPath = "$root\.env"
$checks.EnvHasKeys = $false
if (Test-Path $envPath) {
    $envText = Get-Content $envPath -Raw
    $checks.EnvHasKeys = ($envText -notmatch "your-openai-key") -and ($envText -notmatch "your-anthropic-key") -and ($envText -match "sk-[A-Za-z0-9]")
}

# Check 4: GitHub CLI authenticated
$checks.GhAuth = $false
try {
    $gh = gh auth status 2>$null
    $checks.GhAuth = $gh -match "Logged in to github.com"
} catch {}

# Check 5: Codex CLI authenticated (rough)
$checks.CodexAuth = Test-Path "$env:USERPROFILE\.codex\config.toml"

# Check 6: node_repl pipe present
$checks.NodeReplPipe = Test-Path "\\.\pipe\codex-computer-use" -ErrorAction SilentlyContinue

Write-Host "`n=== GATE 1 DEFEAT CHECKLIST ===" -ForegroundColor Cyan
foreach ($k in $checks.Keys) {
    $color = if ($checks[$k]) { "Green" } else { "Red" }
    Write-Host "$k : $($checks[$k])" -ForegroundColor $color
}

if ($checks.Values -contains $false) {
    Write-Host "`nGate 1 still active. Required actions:" -ForegroundColor Yellow
    if (-not $checks.IsAdmin) { Write-Host "  - Restart this PowerShell as Administrator" }
    if (-not $checks.ServiceInstalled) { Write-Host "  - Right-click 'Oneness Admin Install' on Desktop → Run as administrator" }
    if (-not $checks.EnvHasKeys) { Write-Host "  - Edit $envPath with real OPENAI_API_KEY and ANTHROPIC_API_KEY" }
    if (-not $checks.GhAuth) { Write-Host "  - Run: gh auth login" }
    if (-not $checks.CodexAuth) { Write-Host "  - Sign in to Codex CLI / restart Codex desktop app" }
    if (-not $checks.NodeReplPipe) { Write-Host "  - Restart Codex desktop app to rebind node_repl" }
} else {
    Write-Host "`nGate 1 DEFEATED. Proceed to Gate 2: The Distraction Hydra." -ForegroundColor Green
}

$checks | ConvertTo-Json -Depth 2 | Set-Content "$root\memory\logs\gate1_check.json"
