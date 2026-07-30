# GitHub Setup Helper for Oneness System
# Run after: gh auth login
param(
    [Parameter(Mandatory=$false)]
    [string]$RepoName = "oneness-system",

    [Parameter(Mandatory=$false)]
    [string]$Username = $env:GITHUB_USERNAME,

    [Parameter(Mandatory=$false)]
    [switch]$Private
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
cd $root

# Verify gh auth
$status = gh auth status 2&1 | Out-String
if ($status -notmatch "Logged in to github.com") {
    Write-Host "[ERROR] Not logged into GitHub. Run: gh auth login" -ForegroundColor Red
    exit 1
}

if (-not $Username) {
    $Username = (gh api user -q '.login')
}

Write-Host "Creating GitHub repo: $Username/$RepoName" -ForegroundColor Cyan

# Create repo
$visibility = if ($Private) { "--private" } else { "--public" }
gh repo create "$RepoName" $visibility --source=. --remote=origin --push

Write-Host "Repo live at: https://github.com/$Username/$RepoName" -ForegroundColor Green
Write-Host "Next: add .env to .gitignore if not already, then commit the drops." -ForegroundColor Yellow
