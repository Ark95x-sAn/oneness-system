# Launch Claude Code in target directory
param([string]$Directory = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem")
Push-Location $Directory
npx @anthropic-ai/claude-code
Pop-Location
