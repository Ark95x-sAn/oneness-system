# Open Google Chrome - free web browser (replaces Perplexity Comet integration)
$chromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (Test-Path $chromePath) {
    Start-Process $chromePath -ArgumentList 'https://www.google.com'
    Write-Host 'Chrome launched successfully.'
} else {
    Write-Error 'Chrome not found at $chromePath'
}