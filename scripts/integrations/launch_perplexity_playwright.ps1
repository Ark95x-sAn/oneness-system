# Open Perplexity in Playwright browser for automation
$env:PLAYWRIGHT_CLI_SESSION = "oneness_perplexity"
npx --yes --package @playwright/cli playwright-cli --session oneness_perplexity open https://www.perplexity.ai --headed
