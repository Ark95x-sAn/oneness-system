#Requires -RunAsAdministrator
$log = "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\memory\logs\pc_optimize.log"
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg" | Tee-Object -FilePath $log -Append }
Log "=== PC Optimization started ==="

# 1. Clean temp files (safe only)
Log "Cleaning temp files..."
$tempFolders = @($env:TEMP, 'C:\Windows\Temp')
$totalFreed = 0
foreach ($folder in $tempFolders) {
    if (Test-Path $folder) {
        $before = (Get-ChildItem $folder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $folder -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $folder -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $freed = [math]::Round(($before - $after) / 1MB, 1)
        $totalFreed += $freed
        Log "Cleaned $folder -> freed $freed MB"
    }
}
Log "Total temp freed: $totalFreed MB"

# 2. Empty Recycle Bin
Log "Emptying Recycle Bin..."
try {
    (New-Object -ComObject Shell.Application).Namespace(0xA).Items() | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
    Log "Recycle Bin emptied"
} catch { Log "Could not empty Recycle Bin: $_" }

# 3. Run Windows disk cleanup (sagerun:1)
Log "Running Disk Cleanup..."
Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
Log "Disk Cleanup complete"

# 4. Set power plan to Ultimate Performance if available
Log "Setting high performance power plan..."
$ultimate = powercfg /list | Select-String -Pattern 'Ultimate Performance' | ForEach-Object { ($_ -split '\s+')[3] } | Select-Object -First 1
if ($ultimate) {
    powercfg /setactive $ultimate
    Log "Activated Ultimate Performance plan"
} else {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Log "Activated High Performance plan"
}

# 5. Disable unnecessary visual effects
Log "Tuning visual effects for performance..."
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
if (-not (Test-Path $regPath)) { New-Item $regPath -Force | Out-Null }
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord -Force
Log "Visual effects set to 'Adjust for best performance'"

# 6. Disable transparency
Log "Disabling transparency..."
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord -Force

# 7. Stop non-essential services
try {
    $services = @('DiagTrack', 'dmwappushservice', 'MapsBroker', 'WbioSrvc', 'Fax')
    foreach ($svc in $services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Log "Stopped and disabled $svc"
        }
    }
} catch { Log "Service tuning error: $_" }

# 8. Optimize drives (SSD trim / HDD defrag)
Log "Optimizing drives..."
Get-Volume | Where-Object { $_.DriveLetter -eq 'C' } | Optimize-Volume -Analyze -Defrag -ErrorAction SilentlyContinue | Out-Null
Log "Drive optimization complete"

Log "=== PC Optimization completed ==="
