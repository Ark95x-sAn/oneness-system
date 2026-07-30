# Launch OpenAI Codex CLI in target directory
param([string]$Directory = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem")
Push-Location $Directory
npx openai-codex
Pop-Location
