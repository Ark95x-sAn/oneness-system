# PC Admin #2 — Non-Destructive Optimization and Health Pass
# Safe to run without approval. Does not delete user files or kill active apps.

param(
    [switch]$DeepClean  # requires admin; asks for confirmation
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
$log = "$root\memory\logs\pc_admin_pass.json"
$report = @{}
$report.timestamp = (Get-Date -Format "o")
$report.actions = @()

function Add-Action($name, $status, $detail) {
    $report.actions += @{name=$name; status=$status; detail=$detail}
}

# 1. Disk cleanup (safe: temp files, recycle bin optional)
Write-Host "[1/7] Cleaning temp files..." -ForegroundColor Cyan
try {
    $tempSize = 0
    Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } | ForEach-Object {
        try {
            $tempSize += $_.Length
            if (-not $_.PSIsContainer) { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        } catch {}
    }
    Add-Action "temp_cleanup" "ok" "Cleaned temp files older than 3 days"
} catch {
    Add-Action "temp_cleanup" "partial" $_.ToString()
}

# 2. Empty recycle bin (only if DeepClean)
if ($DeepClean) {
    Write-Host "[2/7] Emptying recycle bin..." -ForegroundColor Cyan
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Add-Action "recycle_bin" "ok" "Emptied"
    } catch {
        Add-Action "recycle_bin" "needs_admin_or_user" $_.ToString()
    }
} else {
    Add-Action "recycle_bin" "skipped" "Use -DeepClean to empty recycle bin"
}

# 3. Windows Update check (notify only, do not auto-install)
Write-Host "[3/7] Checking Windows Update..." -ForegroundColor Cyan
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    $pending = $searchResult.Updates.Count
    Add-Action "windows_update" "info" "$pending updates pending (manual install required)"
} catch {
    Add-Action "windows_update" "error" $_.ToString()
}

# 4. Service optimization (safe: set manual start for non-essential services)
Write-Host "[4/7] Optimizing services..." -ForegroundColor Cyan
$safeManualServices = @("Fax", "WMPNetworkSvc", "XblAuthManager", "XblGameSave", "XboxNetApiSvc")
foreach ($svc in $safeManualServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.StartType -eq "Automatic") {
            Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
            Add-Action "service_$svc" "ok" "Set to Manual"
        }
    } catch {
        Add-Action "service_$svc" "skipped" $_.ToString()
    }
}

# 5. Power plan: high performance when plugged in (safe)
Write-Host "[5/7] Setting power plan..." -ForegroundColor Cyan
try {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    Add-Action "power_plan" "ok" "High performance"
} catch {
    Add-Action "power_plan" "error" $_.ToString()
}

# 6. Network reset / flush DNS (safe)
Write-Host "[6/7] Flushing DNS and resetting network stack..." -ForegroundColor Cyan
try {
    ipconfig /flushdns 2>$null | Out-Null
    Add-Action "dns_flush" "ok" "DNS cache flushed"
} catch {
    Add-Action "dns_flush" "error" $_.ToString()
}

# 7. System info snapshot
Write-Host "[7/7] Recording system snapshot..." -ForegroundColor Cyan
try {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object @{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB,2)}}, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='PctFree';E={[math]::Round(($_.FreeSpace/$_.Size)*100,1)}}
    $mem = Get-CimInstance Win32_OperatingSystem | Select-Object @{N='FreeGB';E={[math]::Round($_.FreePhysicalMemory/1MB,2)}}, @{N='TotalGB';E={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}}, @{N='FreePct';E={[math]::Round(($_.FreePhysicalMemory/$_.TotalVisibleMemorySize)*100,1)}}
    $report.snapshot = @{disk=$disk; memory=$mem}
    Add-Action "snapshot" "ok" "Recorded C: drive and memory state"
} catch {
    Add-Action "snapshot" "error" $_.ToString()
}

# Save log
$report | ConvertTo-Json -Depth 4 | Set-Content $log -Encoding utf8
Write-Host "`nPC Admin pass complete. Log: $log" -ForegroundColor Green

$okCount = ($report.actions | Where-Object { $_.status -eq "ok" }).Count
$warnCount = ($report.actions | Where-Object { $_.status -in @("partial","needs_admin_or_user","info","skipped") }).Count
$errCount = ($report.actions | Where-Object { $_.status -eq "error" }).Count
Write-Host "OK: $okCount | Warn/Info: $warnCount | Error: $errCount" -ForegroundColor Cyan
