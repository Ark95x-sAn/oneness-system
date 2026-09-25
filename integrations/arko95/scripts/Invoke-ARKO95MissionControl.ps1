[CmdletBinding()]
param(
    [ValidateSet('Status','New','Plan','QueueDuty','Sync','Hold','Resume','Abort','VerifyChain')]
    [string]$Action = 'Status',
    [string]$MissionId,
    [int]$ExpectedVersion = 0,
    [string]$Objective,
    [ValidateSet('Mirror','Forge','Challenge','Witness','Remember')][string]$Mode = 'Forge',
    [ValidateSet('observe.system_health','audit.receipt_chain','verify.delegation_receipt','report.operations_brief','maintain.operations_workspace')]
    [string]$Capability = 'observe.system_health',
    [string]$Reason = 'owner_cli_action',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $ProjectRoot 'shell\Arko95.MissionControl.psm1') -Force

function Require-MissionVersion {
    if ([string]::IsNullOrWhiteSpace($MissionId) -or $ExpectedVersion -lt 1) {
        throw "$Action requires -MissionId and a positive -ExpectedVersion from a fresh Status read."
    }
}

$result = switch ($Action) {
    'Status' { Get-Arko95MissionControlStatus -ProjectRoot $ProjectRoot }
    'VerifyChain' { Test-Arko95MissionControlChain -ProjectRoot $ProjectRoot }
    'New' {
        if ([string]::IsNullOrWhiteSpace($Objective)) { throw 'New requires -Objective.' }
        New-Arko95Mission -ProjectRoot $ProjectRoot -Objective $Objective -Mode $Mode
    }
    'Plan' { Require-MissionVersion; Start-Arko95MissionPlan -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion }
    'QueueDuty' { Require-MissionVersion; Add-Arko95MissionDuty -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion -Capability $Capability }
    'Sync' { Require-MissionVersion; Sync-Arko95MissionExecution -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion }
    'Hold' { Require-MissionVersion; Stop-Arko95Mission -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion -Action Hold -Reason $Reason }
    'Resume' { Require-MissionVersion; Stop-Arko95Mission -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion -Action Resume -Reason $Reason }
    'Abort' { Require-MissionVersion; Stop-Arko95Mission -ProjectRoot $ProjectRoot -MissionId $MissionId -ExpectedVersion $ExpectedVersion -Action Abort -Reason $Reason }
}

$result | ConvertTo-Json -Depth 32
