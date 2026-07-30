# Open Blackbox AI in Playwright browser
$env:PLAYWRIGHT_CLI_SESSION = "oneness_blackbox"
npx --yes --package @playwright/cli playwright-cli --session oneness_blackbox open https://www.blackbox.ai --headed
