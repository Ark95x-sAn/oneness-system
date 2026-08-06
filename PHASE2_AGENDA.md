# PHASE 2 AGENDA
## Goal
Fix prime doctor ready

## Steps
1. Installer script
2. Update prime commands
3. Archive raw JSONs
4. Run elevated installer
5. Verify

## STATUS UPDATE — 2026-08-06 (latest)

### Done ✅
1. Created install_oneness_web_service.ps1.
2. Updated prime-cli/src/prime/commands.py to manage the OnenessWeb service.
3. Archived old raw JSONs.
4. Fixed file_ops.py and web_research.py output parsing.
5. Tuned orchestrate.py CPU guard to always run bot team.
6. Verified AURA cycle: cpu_ops ✅, cleanup_ops ✅, file_ops ✅ (found cases/rsb_nordskog).
7. Created desktop helper RUN_INSTALLER_AS_ADMIN.bat.

### Blocker ⚠️
OnenessWeb service still runs old publish build as NT AUTHORITY\SYSTEM; this shell cannot stop/replace it.

### Action needed
Double-click RUN_INSTALLER_AS_ADMIN.bat on desktop, click Yes on UAC.

### Alternative
Restart Codex desktop app as Administrator.

### Verify after
venv\Scripts\prime.exe doctor --json
venv\Scripts\prime.exe status --json
venv\Scripts\python.exe src\subagents\orchestrate.py --cycle --no-alert
