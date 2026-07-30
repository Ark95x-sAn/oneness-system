# MAX ORCHESTRATION — Register Passive Automation Scheduled Tasks
# Safe: no real money spent, no destructive actions, demo mode only.

param(
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
$tasks = @(
    @{Name="Oneness-Daily"; Path="\Oneness"; Description="Daily passive orchestration: PC admin, aura, 852 pulse, N95, memory index, paper bot"; Command="powershell.exe"; Args="-ExecutionPolicy Bypass -File `"$root\scripts\daily_orchestration.ps1`""; Trigger="Daily"; Time="06:00"},
    @{Name="Oneness-Weekly"; Path="\Oneness"; Description="Weekly orchestration: content bundle, all quads, property re-score"; Command="powershell.exe"; Args="-ExecutionPolicy Bypass -File `"$root\scripts\weekly_orchestration.ps1`""; Trigger="Weekly"; Time="12:00"; Days="Sunday"},
    @{Name="Oneness-AuraAtLogon"; Path="\Oneness"; Description="Start aura subagents at user logon"; Command="powershell.exe"; Args="-ExecutionPolicy Bypass -Command `"cd '$root'; .\venv\Scripts\prime.exe aura start`""; Trigger="AtLogon"}
)

foreach ($t in $tasks) {
    if ($Unregister) {
        Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Unregistered: $($t.Name)" -ForegroundColor Yellow
        continue
    }

    Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute $t.Command -Argument $t.Args
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

    if ($t.Trigger -eq "Daily") {
        $trigger = New-ScheduledTaskTrigger -Daily -At $t.Time
    } elseif ($t.Trigger -eq "Weekly") {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $t.Days -At $t.Time
    } elseif ($t.Trigger -eq "AtLogon") {
        $trigger = New-ScheduledTaskTrigger -AtLogon
    }

    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

    try {
        Register-ScheduledTask -TaskName $t.Name -TaskPath "Oneness" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $t.Description -Force | Out-Null
        Write-Host "Registered: $($t.Name) [$($t.Trigger)]" -ForegroundColor Green
    } catch {
        Write-Host "Failed to register $($t.Name): $_" -ForegroundColor Red
    }
}

if (-not $Unregister) {
    Write-Host "`nMAX ORCHESTRATION ACTIVE — scheduled tasks registered under \Oneness" -ForegroundColor Cyan
    Get-ScheduledTask -TaskPath "\Oneness" | Select-Object TaskName, State, NextRunTime | Format-Table -AutoSize
}
