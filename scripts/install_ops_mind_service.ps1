#requires -Version 5.1
<#
.SYNOPSIS
    Install the Operations Mind as a Windows Scheduled Task.
.DESCRIPTION
    Creates a scheduled task that runs the Operations Mind oversight cycle
    every 5 minutes in the background. All actions are safe/read-only;
    remediation scripts are preview-only and never auto-executed.
.PARAMETER Interval
    Task run interval in minutes (default: 5).
.PARAMETER Remove
    Remove the scheduled task instead of creating it.
#>
param(
    [int]$Interval = 5,
    [switch]$Remove
)

$taskName = "Oneness-OperationsMind"
$root = "$env:USERPROFILE\OneDrive\Desktop\OnenessSystem"
$python = "$root\venv\Scripts\python.exe"
if (-not (Test-Path $python)) { $python = "python" }

if ($Remove) {
    Write-Host "Removing scheduled task: $taskName"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed."
    exit 0
}

Write-Host "Installing Operations Mind scheduled task..."
Write-Host "  Name: $taskName"
Write-Host "  Interval: every $Interval minute(s)"
Write-Host "  Python: $python"

$action = New-ScheduledTaskAction `
    -Execute $python `
    -Argument "-m src.ops_mind.mind --cycle" `
    -WorkingDirectory $root

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $Interval)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERDOMAIN\$env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OnenessSystem Operations Mind - unified PC oversight (safe, read-only monitoring)" `
    -Force

Write-Host ""
Write-Host "Installed. The Operations Mind will run every $Interval minute(s)."
Write-Host "View status: Get-ScheduledTask -TaskName '$taskName' | Get-ScheduledTaskInfo"
Write-Host "Remove: .\scripts\install_ops_mind_service.ps1 -Remove"