[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$modulePath = Join-Path $ProjectRoot 'shell\Arko95.Core.psm1'
$registryPath = Join-Path $ProjectRoot 'config\connector-registry.json'
$rosterPath = Join-Path $ProjectRoot 'config\delegation-roster.json'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { throw "PowerShell parse errors in ${modulePath}: $($parseErrors -join '; ')" }

Import-Module $modulePath -Force
$registry = Get-Arko95ConnectorRegistry -ProjectRoot $ProjectRoot
$expectedIds = @('cactus_real_estate','conductor','data_analytics','google_drive','investigations','magicpath','nvidia_skills','plugin_management','windows_security')
$actualIds = @($registry.connectors | ForEach-Object { [string]$_.id } | Sort-Object)
if (($actualIds -join '|') -ne ($expectedIds -join '|')) { throw 'The toolbelt does not contain exactly the requested nine stable connector IDs.' }

foreach ($connector in @($registry.connectors)) {
    if ($connector.default_effect -ne 'proposal_only' -or $connector.execution_authority -ne $false -or $connector.unattended_eligible -ne $false -or $connector.operations_vp_eligible -ne $false) {
        throw "Connector $($connector.id) gained authority."
    }
    if (-not $connector.requires_live_verification -or $connector.credential_mode -ne 'host_managed_only') {
        throw "Connector $($connector.id) lost its live-verification or host-managed credential boundary."
    }
}

$specialistIds = @('scout','architect','challenger','verifier','archivist')
foreach ($specialistId in $specialistIds) {
    $toolbelt = Get-Arko95SpecialistToolbelt -ProjectRoot $ProjectRoot -SpecialistId $specialistId
    if ($toolbelt.Effect -ne 'routing_hints_only' -or $toolbelt.AutoInvoke -ne $false -or $toolbelt.RegistryDigest -notmatch '^[a-f0-9]{64}$') {
        throw "Specialist $specialistId gained tool invocation authority."
    }
    if (@($toolbelt.Connectors).Count -lt 1) { throw "Specialist $specialistId received no bounded routing hints." }
}

$stateRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'state'))
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $stateRoot ('test-toolbelt-{0}' -f [guid]::NewGuid().ToString('N'))))
if (-not $fixtureRoot.StartsWith($stateRoot + [System.IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Toolbelt fixture escaped the project state directory.' }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

try {
    $queue = Join-Path $fixtureRoot 'intents.jsonl'
    $delegationQueue = Join-Path $fixtureRoot 'delegations.jsonl'
    $planPath = Join-Path $fixtureRoot 'latest-delegation.json'
    $handoffPath = Join-Path $fixtureRoot 'latest-handoff.txt'
    $proposal = New-Arko95DelegationProposal -ProjectRoot $ProjectRoot -Mode 'Witness' -Intent 'Review the bounded connector routing contract.' -QueuePath $queue -DelegationQueuePath $delegationQueue -PlanPath $planPath -HandoffPath $handoffPath
    $plan = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json -DateKind String
    if ($plan.toolbelt.connector_count -ne 9 -or $plan.toolbelt.auto_invoke -ne $false -or $plan.toolbelt.grants_authority -ne $false) { throw 'The generated plan expanded toolbelt authority.' }
    if ($plan.toolbelt.registry_digest -notmatch '^[a-f0-9]{64}$' -or -not (Test-Arko95DelegationReceipt -PlanPath $planPath)) { throw 'The plan did not bind and preserve its registry digest.' }
    foreach ($task in @($plan.tasks)) {
        if ($task.toolbelt_effect -ne 'routing_hints_only' -or $task.toolbelt_auto_invoke -ne $false -or $task.toolbelt_live_verification_required -ne $true) {
            throw "Delegation task $($task.task_id) gained connector authority."
        }
        foreach ($connectorId in @($task.toolbelt_connector_ids)) {
            if ($connectorId -notin $actualIds) { throw "Delegation task $($task.task_id) referenced unknown connector '$connectorId'." }
        }
    }
    if ($proposal.Handoff -notmatch 'A hint is not a tool call' -or $proposal.Handoff -notmatch 'untrusted data') { throw 'The handoff omitted its live connector and prompt-injection warning.' }

    $invalidRoot = Join-Path $fixtureRoot 'invalid-project'
    $invalidConfig = Join-Path $invalidRoot 'config'
    New-Item -ItemType Directory -Path $invalidConfig -Force | Out-Null
    Copy-Item -LiteralPath $rosterPath -Destination (Join-Path $invalidConfig 'delegation-roster.json') -Force
    $invalidRegistry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json -DateKind String
    $invalidRegistry.connectors[0] | Add-Member -NotePropertyName 'endpoint' -NotePropertyValue 'https://untrusted.invalid'
    [System.IO.File]::WriteAllText((Join-Path $invalidConfig 'connector-registry.json'),($invalidRegistry | ConvertTo-Json -Depth 24),[System.Text.UTF8Encoding]::new($false))
    $forbiddenFieldBlocked = $false
    try { Get-Arko95ConnectorRegistry -ProjectRoot $invalidRoot | Out-Null } catch { $forbiddenFieldBlocked = $true }
    if (-not $forbiddenFieldBlocked) { throw 'The connector registry accepted a configuration-supplied endpoint.' }

    [pscustomobject]@{
        ok = $true
        connector_count = $actualIds.Count
        specialist_count = $specialistIds.Count
        effect = 'routing_hints_only'
        auto_invoke = $false
        registry_digest_bound = $true
        forbidden_field_rejection = 'verified'
        handoff_injection_warning = 'verified'
    } | ConvertTo-Json -Depth 5
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
