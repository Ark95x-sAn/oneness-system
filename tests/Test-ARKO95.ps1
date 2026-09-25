[CmdletBinding()]
param([string]$ProjectRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$modulePath = Join-Path $ProjectRoot 'shell\Arko95.Core.psm1'
$operationsModulePath = Join-Path $ProjectRoot 'shell\Arko95.Operations.psm1'
$missionModulePath = Join-Path $ProjectRoot 'shell\Arko95.MissionControl.psm1'
$learningModulePath = Join-Path $ProjectRoot 'shell\Arko95.DecisionLearning.psm1'
$shellPath = Join-Path $ProjectRoot 'shell\ARKO95.PetShell.ps1'
$missionShellPath = Join-Path $ProjectRoot 'shell\ARKO95.MissionControl.ps1'
$operationsRunnerPath = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95OperationsVP.ps1'
$operationsInstallerPath = Join-Path $ProjectRoot 'scripts\Install-ARKO95OperationsVP.ps1'
$toolbeltTestPath = Join-Path $ProjectRoot 'tests\Test-Toolbelt.ps1'
$missionTestPath = Join-Path $ProjectRoot 'tests\Test-MissionControl.ps1'
$learningRunnerPath = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95DecisionLearning.ps1'
$adapterRefreshPath = Join-Path $ProjectRoot 'scripts\Update-ARKO95AdapterObservations.ps1'
$learningTestPath = Join-Path $ProjectRoot 'tests\Test-DecisionLearning.ps1'
$rosterPath = Join-Path $ProjectRoot 'config\delegation-roster.json'
$registryPath = Join-Path $ProjectRoot 'config\connector-registry.json'

foreach ($path in @($modulePath, $operationsModulePath, $missionModulePath, $learningModulePath, $shellPath, $missionShellPath, $operationsRunnerPath, $operationsInstallerPath, $learningRunnerPath, $adapterRefreshPath, $toolbeltTestPath, $missionTestPath, $learningTestPath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse errors in ${path}: $($errors -join '; ')" }
}

Import-Module $modulePath -Force
$roster = Get-Content -Raw -LiteralPath $rosterPath | ConvertFrom-Json
if ($roster.schema_version -ne 1) { throw 'Delegation roster schema is invalid.' }
$registry = Get-Arko95ConnectorRegistry -ProjectRoot $ProjectRoot
$expectedConnectorIds = @('cactus_real_estate','conductor','data_analytics','google_drive','investigations','magicpath','nvidia_skills','plugin_management','windows_security')
if ((@($registry.connectors | ForEach-Object { [string]$_.id } | Sort-Object) -join '|') -ne ($expectedConnectorIds -join '|')) {
    throw 'The connector registry does not contain exactly the requested nine-tool belt.'
}
foreach ($connector in @($registry.connectors)) {
    if ($connector.execution_authority -ne $false -or $connector.unattended_eligible -ne $false -or $connector.operations_vp_eligible -ne $false -or $connector.default_effect -ne 'proposal_only') {
        throw "Connector $($connector.id) gained execution, unattended, Operations VP, or non-proposal authority."
    }
}
$profile = $null
foreach ($mode in @('Mirror','Forge','Challenge','Witness','Remember')) {
    $modeProfile = Get-Arko95DelegationProfile -ProjectRoot $ProjectRoot -Mode $mode
    if (@($modeProfile.Specialists).Count -ne 3 -or $modeProfile.MaxParallel -ne 3) { throw "$mode did not select the bounded three-specialist crew." }
    if (@($modeProfile.Specialists | Where-Object { $_.execution_authority -or $_.may_write -or $_.may_spawn }).Count -ne 0) {
        throw "A $mode specialist gained authority, write access, or nested delegation."
    }
    if ($mode -eq 'Forge') { $profile = $modeProfile }
}

$status = Get-Arko95Status -ProjectRoot $ProjectRoot
if ($status.Effect -ne 'proposal_only') { throw 'Status effect must remain proposal_only.' }
if ($status.Host -ne 'NETXHQ') { throw 'PC binding did not resolve to NETXHQ.' }

$testDir = Join-Path $ProjectRoot 'state\test'
$queue = Join-Path $testDir 'intents.jsonl'
$delegationQueue = Join-Path $testDir 'delegations.jsonl'
$latestPlan = Join-Path $testDir 'latest-delegation.json'
$testHandoff = Join-Path $testDir 'latest-handoff.txt'
if (Test-Path -LiteralPath $testDir) { Remove-Item -LiteralPath $testDir -Recurse -Force }
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

try {
    $proposal = New-Arko95IntentProposal -ProjectRoot $ProjectRoot -Mode 'Mirror' -Intent 'Summarize the current local mission state.' -QueuePath $queue -HandoffPath $testHandoff
    if (-not (Test-Path -LiteralPath $queue)) { throw 'Intent queue was not created.' }
    $record = Get-Content -LiteralPath $queue | Select-Object -Last 1 | ConvertFrom-Json
    if ($record.execution_authority -ne $false) { throw 'Intent proposal gained execution authority.' }
    if ($record.requested_effect -ne 'proposal_only') { throw 'Intent proposal effect changed.' }
    if ($proposal.Handoff -notmatch 'not execution authority') { throw 'Handoff is missing its authority boundary.' }

    $delegated = New-Arko95DelegationProposal -ProjectRoot $ProjectRoot -Mode 'Forge' -Intent 'Build the smallest local testable improvement.' -QueuePath $queue -DelegationQueuePath $delegationQueue -PlanPath $latestPlan -HandoffPath $testHandoff
    if ($delegated.Effect -ne 'proposal_only' -or $delegated.SpecialistCount -ne 3) { throw 'Delegation proposal escaped its bounded effect or crew cap.' }
    foreach ($path in @($delegationQueue, $latestPlan, $testHandoff)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Delegation artifact was not created: $path" }
    }
    $plan = Get-Content -Raw -LiteralPath $latestPlan | ConvertFrom-Json
    if ($plan.execution_authority -ne $false -or $plan.requested_effect -ne 'proposal_only') { throw 'Delegation plan gained execution authority.' }
    if ($plan.policy.max_parallel_specialists -ne 3 -or $plan.policy.max_concurrent_specialist_writers -ne 0 -or $plan.policy.nested_delegation -ne $false) {
        throw 'Delegation policy changed its concurrency, writer, or nesting boundary.'
    }
    if ($plan.coordinator.owns_final_judgment -ne $true -or $plan.parent_integration_gate.final_judgment_owner -ne 'arko95-parent') {
        throw 'Final judgment did not remain with the parent integrator.'
    }
    $scoutToolbelt = Get-Arko95SpecialistToolbelt -ProjectRoot $ProjectRoot -SpecialistId 'scout'
    if ($plan.toolbelt.connector_count -ne 9 -or $plan.toolbelt.default_effect -ne 'proposal_only' -or $plan.toolbelt.auto_invoke -ne $false -or $plan.toolbelt.grants_authority -ne $false) {
        throw 'The delegation plan toolbelt gained authority or lost its nine connectors.'
    }
    if ($plan.toolbelt.registry_digest -ne $scoutToolbelt.RegistryDigest -or $plan.toolbelt.registry_digest -notmatch '^[a-f0-9]{64}$') {
        throw 'The delegation plan did not bind the exact connector registry digest.'
    }
    $expectedFields = @('conclusion','evidence','files_and_lines','tests_or_checks','risks','recommended_parent_action')
    if ((@($plan.result_contract) -join '|') -ne ($expectedFields -join '|')) { throw 'The six-field specialist result contract changed.' }
    if (@($plan.tasks).Count -ne 3) { throw 'The delegation plan did not contain exactly three bounded tasks.' }
    foreach ($task in @($plan.tasks)) {
        if ($task.execution_authority -ne $false -or $task.may_write -ne $false -or $task.may_spawn -ne $false) {
            throw "Task $($task.task_id) gained forbidden authority."
        }
        if ((@($task.expected_return_fields) -join '|') -ne ($expectedFields -join '|')) { throw "Task $($task.task_id) has the wrong result contract." }
        if ($task.toolbelt_effect -ne 'routing_hints_only' -or $task.toolbelt_auto_invoke -ne $false -or $task.toolbelt_live_verification_required -ne $true) {
            throw "Task $($task.task_id) gained connector invocation authority."
        }
        $registeredIds = @($registry.connectors | ForEach-Object { [string]$_.id })
        foreach ($connectorId in @($task.toolbelt_connector_ids)) {
            if ($connectorId -notin $registeredIds) { throw "Task $($task.task_id) contains an unregistered toolbelt hint '$connectorId'." }
        }
    }
    if ($plan.receipt_sha256 -notmatch '^[a-f0-9]{64}$' -or $plan.receipt_sha256 -ne $delegated.DelegationDigest) { throw 'Delegation receipt digest is missing or inconsistent.' }
    if ($plan.receipt_algorithm -ne 'sha256_utf8_canonical_json_without_receipt_datekind_string') { throw 'Delegation receipt algorithm is missing.' }
    if (-not (Test-Arko95DelegationReceipt -PlanPath $latestPlan)) { throw 'Delegation receipt did not survive canonical verification.' }
    if ($delegated.Handoff -notmatch 'planning authority only' -or $delegated.Handoff -notmatch 'PARENT INTEGRATION GATE' -or $delegated.Handoff -notmatch 'verify live availability') {
        throw 'Delegation handoff is missing its authority or parent-integration boundary.'
    }

    $invalidRoot = Join-Path $testDir 'invalid-registry-project'
    $invalidConfig = Join-Path $invalidRoot 'config'
    New-Item -ItemType Directory -Path $invalidConfig -Force | Out-Null
    Copy-Item -LiteralPath $rosterPath -Destination (Join-Path $invalidConfig 'delegation-roster.json') -Force
    $invalidRegistry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json -DateKind String
    $invalidRegistry.connectors[0] | Add-Member -NotePropertyName 'command' -NotePropertyValue 'whoami'
    [System.IO.File]::WriteAllText((Join-Path $invalidConfig 'connector-registry.json'),($invalidRegistry | ConvertTo-Json -Depth 24),[System.Text.UTF8Encoding]::new($false))
    $forbiddenFieldBlocked = $false
    try { Get-Arko95ConnectorRegistry -ProjectRoot $invalidRoot | Out-Null } catch { $forbiddenFieldBlocked = $true }
    if (-not $forbiddenFieldBlocked) { throw 'A connector registry executable field was accepted.' }

    $escapePath = Join-Path $ProjectRoot ('escape-test-{0}.jsonl' -f [guid]::NewGuid().ToString('N'))
    $escapeBlocked = $false
    try {
        New-Arko95IntentProposal -ProjectRoot $ProjectRoot -Mode 'Mirror' -Intent 'Test the project state write boundary.' -QueuePath $escapePath -HandoffPath $testHandoff | Out-Null
    }
    catch { $escapeBlocked = $true }
    if (-not $escapeBlocked) { throw 'A caller-supplied path escaped the project state directory.' }
    if (Test-Path -LiteralPath $escapePath) { throw 'The rejected path escape created a file.' }

    $blocked = $false
    try {
        New-Arko95IntentProposal -ProjectRoot $ProjectRoot -Mode 'Forge' -Intent 'api_key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456' -QueuePath $queue -HandoffPath $testHandoff | Out-Null
    }
    catch { $blocked = $true }
    if (-not $blocked) { throw 'Credential-like text was not rejected.' }
}
finally {
    if (Test-Path -LiteralPath $testDir) { Remove-Item -LiteralPath $testDir -Recurse -Force }
}

$shellOutput = & pwsh.exe -NoLogo -NoProfile -STA -File $shellPath -ProjectRoot $ProjectRoot -TestMode
$shellResult = $shellOutput | ConvertFrom-Json
if (-not $shellResult.ok -or -not $shellResult.xaml_loaded) { throw 'WPF shell smoke test failed.' }
if (-not $shellResult.delegation_ready) { throw 'WPF shell did not load the delegation roster.' }
if ($shellResult.toolbelt_connector_count -ne 9 -or $shellResult.toolbelt_effect -ne 'routing_hints_only') { throw 'WPF shell did not load the bounded nine-tool belt.' }
if (-not $shellResult.operations_module_loaded -or -not $shellResult.stop_control_ready) { throw 'WPF shell did not load the Operations VP status and stop controls.' }
if (-not $shellResult.mission_control_ready) { throw 'WPF shell did not expose the Mission Control entry point.' }

[pscustomobject]@{
    ok = $true
    parsed_files = 13
    status_effect = $status.Effect
    mission_status = $status.MissionStatus
    intent_boundary = 'verified'
    delegation_boundary = 'verified'
    connector_registry = 'nine_gated_routing_hints'
    connector_authority = 'none'
    specialist_cap = $profile.MaxParallel
    wpf_shell = 'loaded'
    operations_status = 'loaded_fail_closed'
    operations_stop_control = 'loaded'
    mission_control = 'entry_point_loaded'
    decision_learning = 'parsed_and_separate'
} | ConvertTo-Json -Depth 4
