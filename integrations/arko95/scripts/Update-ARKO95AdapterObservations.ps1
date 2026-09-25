[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$StateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $ProjectRoot 'shell\Arko95.DecisionLearning.psm1') -Force

Update-Arko95LocalAdapterObservations -ProjectRoot $ProjectRoot -StateRoot $StateRoot | ConvertTo-Json -Depth 12
