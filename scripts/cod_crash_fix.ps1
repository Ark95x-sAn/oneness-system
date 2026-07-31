# Call of Duty Crash Fix — Safe Gaming Stability Script
# Apply these while NOT in a match; restart required for some changes.

$ErrorActionPreference = "Stop"

Write-Host "=== Call of Duty Stability Fixes ===" -ForegroundColor Cyan

# 1. Disable Hardware-Accelerated GPU Scheduling (HAGS) — known cause of CoD crashes
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\HardwareSettings\Persistent\Volatile"
# Actually HAGS is at:
$hagsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-ItemProperty -Path $hagsPath -Name "HwSchMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "[1/7] HAGS disabled (HwSchMode=0). Requires restart." -ForegroundColor Green

# 2. Increase GPU driver timeout (TDR) to prevent "Display driver stopped responding"
Set-ItemProperty -Path $hagsPath -Name "TdrDelay" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $hagsPath -Name "TdrDdiDelay" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "[2/7] TDR timeout increased to 10 seconds. Requires restart." -ForegroundColor Green

# 3. Ensure Game Mode auto-enable is ON
$gameBarPath = "HKCU:\Software\Microsoft\GameBar"
if (-not (Test-Path $gameBarPath)) { New-Item -Path $gameBarPath -Force | Out-Null }
Set-ItemProperty -Path $gameBarPath -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "[3/7] Game Mode auto-enable set to ON." -ForegroundColor Green

# 4. Ensure Game DVR is fully disabled (already disabled, reinforce)
$dvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $dvrPolicy)) { New-Item -Path $dvrPolicy -Force | Out-Null }
Set-ItemProperty -Path $dvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
$dvrUser = "HKCU:\System\GameConfigStore"
Set-ItemProperty -Path $dvrUser -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "[4/7] Game DVR reinforced OFF." -ForegroundColor Green

# 5. Disable fullscreen optimizations for cod.exe and launcher
$codExe = "C:\Program Files (x86)\Call of Duty\_retail_\cod.exe"
$launcherExe = "C:\Program Files (x86)\Call of Duty\Call of Duty Launcher.exe"
foreach ($exe in @($codExe, $launcherExe)) {
    if (Test-Path $exe) {
        # Use reg.exe because AppCompatFlags path is per-exe
        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
        Set-ItemProperty -Path $regKey -Name $exe -Value "~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE" -Type String -Force -ErrorAction SilentlyContinue
        Write-Host "[5/7] Fullscreen optimizations disabled for: $exe" -ForegroundColor Green
    }
}

# 6. Set Windows Graphics Settings to prefer high-performance GPU for CoD
$gpuPrefPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
if (-not (Test-Path $gpuPrefPath)) { New-Item -Path $gpuPrefPath -Force | Out-Null }
foreach ($exe in @($codExe, $launcherExe)) {
    if (Test-Path $exe) {
        Set-ItemProperty -Path $gpuPrefPath -Name $exe -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
        Write-Host "[6/7] High-performance GPU preference set for: $exe" -ForegroundColor Green
    }
}

# 7. Clear DirectX shader cache (safe, can fix rendering crashes)
$shaderCache = "$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache"
if (Test-Path $shaderCache) {
    $before = (Get-ChildItem $shaderCache -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Get-ChildItem $shaderCache -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem $shaderCache -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host "[7/7] DirectX Shader Cache cleared (was $before bytes)." -ForegroundColor Green
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "RESTART your PC for HAGS/TDR changes to take effect." -ForegroundColor Yellow
Write-Host "After restart, launch Call of Duty and test." -ForegroundColor Yellow

