[CmdletBinding()]
param(
    [ValidateSet('Status','Scan','VerifyChain','Backlog','MigratePrivacy')]
    [string]$Action='Status',
    [string]$ProjectRoot,
    [string]$StateRoot,
    [switch]$AcknowledgeGeneratedSnapshotRemoval
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot=Split-Path -Parent $PSScriptRoot }
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $ProjectRoot 'shell\Arko95.Agency.psm1') -Force

$result=switch($Action) {
    'Status' { Get-Arko95AgencyStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
    'Scan' { Invoke-Arko95AgencyScan -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
    'VerifyChain' { Test-Arko95AgencyChain -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
    'Backlog' { [pscustomobject]@{ items=@(Get-Arko95AgencyBacklog -ProjectRoot $ProjectRoot -StateRoot $StateRoot) } }
    'MigratePrivacy' { Invoke-Arko95AgencyPrivacyMigration -ProjectRoot $ProjectRoot -StateRoot $StateRoot -AcknowledgeGeneratedSnapshotRemoval:$AcknowledgeGeneratedSnapshotRemoval }
}
$result | ConvertTo-Json -Depth 40
