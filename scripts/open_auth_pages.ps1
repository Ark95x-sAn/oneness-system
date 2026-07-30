$urls = @(
    "https://claude.ai/login",
    "https://www.perplexity.ai",
    "https://app.blackbox.ai/login",
    "https://github.com/login"
)
foreach ($url in $urls) {
    Write-Host "Opening $url"
    cmd /c "start chrome `"$url`""
    Start-Sleep -Seconds 2
}
Write-Host "Sign in on each page, then run: gh auth login, codex login, .\venv\Scripts\prime.exe auth"
