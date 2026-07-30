# Launch GitHub Copilot CLI
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Write-Error "GitHub CLI not found. Install from https://cli.github.com"
    exit 1
}
gh copilot --help
