[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$EnableLowRisk,
    [ValidateRange(1,60)][int]$IntervalMinutes = 2,
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$taskName = 'ARKO95-OperationsVP'
$runner = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95OperationsVP.ps1'
$module = Join-Path $ProjectRoot 'shell\Arko95.Operations.psm1'

foreach ($requiredPath in @($runner,$module,(Join-Path $ProjectRoot 'config\operations-vp.json'))) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required Operations VP file is missing: $requiredPath" }
}
Import-Module $module -Force

if ($Remove) {
    try { Stop-Arko95Operations -ProjectRoot $ProjectRoot -Reason 'scheduled_task_removed' | Out-Null } catch { }
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    [pscustomobject]@{ removed=$true; task_name=$taskName; operations='stopped'; state_preserved=$true } | ConvertTo-Json
    return
}

$tokens = $null
$parseErrors = $null
foreach ($scriptPath in @($runner,$module,$PSCommandPath)) {
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) { throw "PowerShell parse errors in ${scriptPath}: $($parseErrors -join '; ')" }
}
$null = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
$null = Initialize-Arko95Operations -ProjectRoot $ProjectRoot

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $existingArguments = @($existing.Actions | ForEach-Object { [string]$_.Arguments }) -join ' '
    if ($existingArguments -notlike "*$runner*") { throw "A scheduled task named '$taskName' already exists but does not belong to this ARKO-95 project." }
}

$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -Action Once -ProjectRoot "{1}"' -f $runner,$ProjectRoot
$action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $ProjectRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN,$env:USERNAME) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'ARKO-95 WIZARD Operations VP - bounded R0/R1 local cycle with kill latch and receipts' -Force | Out-Null

if ($EnableLowRisk) {
    $ack = 'I authorize bounded R0/R1 ARKO-95 operations'
    $null = Enable-Arko95Operations -ProjectRoot $ProjectRoot -Acknowledgement $ack
}

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
[pscustomobject]@{
    installed = $true
    task_name = $taskName
    task_state = [string]$task.State
    interval_minutes = $IntervalMinutes
    principal = 'current_user_limited_interactive'
    enabled_low_risk = [bool]$EnableLowRisk
    automatic_scope = @('R0 observation','R1 writes only inside ARKO-95 operations state')
    consequential_actions = 'still require separate foreground approval'
    remove_command = ".\scripts\Install-ARKO95OperationsVP.ps1 -Remove"
} | ConvertTo-Json -Depth 6
