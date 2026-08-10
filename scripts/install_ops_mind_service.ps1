#requires -Version 5.1
<#
.SYNOPSIS
    Install the Operations Mind as a silent background scheduled task.
.DESCRIPTION
    Creates a scheduled task that runs the Operations Mind oversight cycle
    every 10 minutes completely silently - no window, no console flash,
    no stdout output. Uses S4U logon (service-style) and CREATE_NO_WINDOW
    on all subprocess calls. All actions are safe/read-only.
.PARAMETER Interval
    Task run interval in minutes (default: 10).
.PARAMETER Remove
    Remove the scheduled task instead of creating it.
#>
param(
    [int]$Interval = 10,
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

Write-Host "Installing Operations Mind (silent background mode)..."
Write-Host "  Name: $taskName"
Write-Host "  Interval: every $Interval minute(s)"
Write-Host "  Mode: silent (no window, no stdout, file logging only)"

$action = New-ScheduledTaskAction `
    -Execute $python `
    -Argument "-m src.ops_mind.mind --cycle --background" `
    -WorkingDirectory $root

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $Interval)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERDOMAIN\$env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "OnenessSystem Operations Mind - silent background PC oversight" `
    -Force

Write-Host ""
Write-Host "Installed. Runs silently every $Interval minute(s)."
Write-Host "No windows, no console flash, no disruption to your work."
Write-Host ""
Write-Host "Remove: .\scripts\install_ops_mind_service.ps1 -Remove"