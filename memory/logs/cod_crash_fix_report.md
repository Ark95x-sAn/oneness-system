# CALL OF DUTY CRASH DIAGNOSTIC + FIX REPORT
## Generated: 2026-07-30 during CoD session

### System Specs
- CPU: AMD Ryzen 7 9800X3D 8-Core
- GPU: NVIDIA GeForce RTX 5070 Ti (driver 32.0.15.9159, dated 2025-12-10)
- iGPU: AMD Radeon Graphics
- OS: Windows 11 Home Insider Preview 26H1 build 2387
- RAM: ~13.4 GB available currently
- Power plan: High performance

### Game Installations Found
1. C:\Program Files (x86)\Call of Duty\_retail_\cod.exe (Activision launcher)
2. C:\Program Files (x86)\Steam\steamapps\common\Call of Duty HQ\cod.exe (Steam)

### Crash History
- Most recent crash report zip: 2026-07-28 (cod_CL28002244_20260728-182627209.zip)
- Stacktrace shows crash inside cod.exe, with ntdll/kernelbase in chain
- No new crash dumps since July 28, but codCrashHandler process still running
- Crash telemetry file updated 2026-07-29 03:12

### Likely Causes (ranked)
1. **NVIDIA driver 32.0.15.9159 is from December 2025** — very old for RTX 5070 Ti + Windows 11 26H1 Insider. Strongly recommend updating to latest Game Ready driver.
2. **Windows 11 Insider Preview build 26H1 2387** — preview builds often have game-specific bugs and driver compatibility issues.
3. **Hardware-Accelerated GPU Scheduling (HAGS) was ON** — known cause of CoD instability. Disabled.
4. **GPU driver timeout (TDR) was at default 2 seconds** — increased to 10 seconds to prevent display driver recoveries.
5. **Nvidia Reflex set to "Enabled + boost"** in game config — can cause instability on some systems.

### Fixes Applied Now (safe, no restart needed for all)
1. ✅ Disabled HAGS (HwSchMode=0) — takes effect after restart
2. ✅ Increased TdrDelay/TdrDdiDelay to 10 seconds — takes effect after restart
3. ✅ Reinforced Game DVR OFF
4. ✅ Confirmed Game Mode auto-enable ON
5. ✅ Disabled fullscreen optimizations for both CoD executables
6. ✅ Set Windows Graphics Settings to prefer high-performance GPU for both CoD executables

### Fixes Requiring User Action
1. **Restart PC** — HAGS and TDR changes need it.
2. **Update NVIDIA driver** — download latest Game Ready driver from nvidia.com after restart.
3. **Consider changing in-game Nvidia Reflex** from "Enabled + boost" to "Enabled" or "Disabled" if crashes continue.
4. **Verify game files** through Steam or Activision launcher after driver update.

### Monitoring
- Aura GameGuard active — no background ops will disrupt CoD
- PC admin pass completed — 4 OK, 2 info, 0 errors
- System stable; no destructive changes made
