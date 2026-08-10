@echo off
echo === AI Tool Authentication ===
echo.
echo 1. GitHub CLI
call gh auth login --web
echo.
echo 2. Codex CLI
call codex login
echo.
echo 3. Claude Desktop (web sign-in)
start "" "https://claude.ai/login"
echo.
echo 4. Google Chrome (free browser - no sign-in needed)
start "" "https://www.google.com"
echo.
echo 5. BlackBox AI (web sign-in)
start "" "https://app.blackbox.ai/login"
echo.
echo Update .env with real API keys when ready.
pause
