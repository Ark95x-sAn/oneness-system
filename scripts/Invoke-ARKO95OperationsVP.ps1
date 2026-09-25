[CmdletBinding()]
param(
    [ValidateSet('Status','Initialize','Enable','Stop','Once','Loop','Enqueue')]
    [string]$Action = 'Status',
    [ValidateSet('observe.system_health','audit.receipt_chain','verify.delegation_receipt','report.operations_brief','maintain.operations_workspace')]
    [string]$Capability = 'observe.system_health',
    [string]$IdempotencyKey,
    [string]$Acknowledgement,
    [string]$Reason = 'owner_stop',
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$modulePath = Join-Path $ProjectRoot 'shell\Arko95.Operations.psm1'
Import-Module $modulePath -Force

function Write-ResultJson {
    param($Value)
    $Value | ConvertTo-Json -Depth 24
}

switch ($Action) {
    'Status' { Write-ResultJson (Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot) }
    'Initialize' { Write-ResultJson (Initialize-Arko95Operations -ProjectRoot $ProjectRoot) }
    'Enable' { Write-ResultJson (Enable-Arko95Operations -ProjectRoot $ProjectRoot -Acknowledgement $Acknowledgement) }
    'Stop' { Write-ResultJson (Stop-Arko95Operations -ProjectRoot $ProjectRoot -Reason $Reason) }
    'Once' { Write-ResultJson (Invoke-Arko95OperationsCycle -ProjectRoot $ProjectRoot) }
    'Enqueue' {
        if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'Enqueue requires -IdempotencyKey.' }
        Write-ResultJson (New-Arko95OperationsDuty -ProjectRoot $ProjectRoot -Capability $Capability -IdempotencyKey $IdempotencyKey -Parameters ([ordered]@{}) -RequestedBy 'local_owner_cli')
    }
    'Loop' {
        $policy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
        $interval = [int]$policy.scheduler.cycle_interval_seconds
        while ($true) {
            $status = Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot
            if (-not $status.Initialized -or $status.DesiredState -ne 'running' -or $status.KillLatched) { break }
            try { Write-ResultJson (Invoke-Arko95OperationsCycle -ProjectRoot $ProjectRoot) }
            catch {
                [pscustomobject]@{ status='faulted'; error=$_.Exception.Message; timestamp=[DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
                break
            }
            Start-Sleep -Seconds $interval
        }
    }
}
