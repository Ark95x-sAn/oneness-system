[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$modulePath = Join-Path $ProjectRoot 'shell\Arko95.MissionControl.psm1'
$operationsModulePath = Join-Path $ProjectRoot 'shell\Arko95.Operations.psm1'
$dashboardPath = Join-Path $ProjectRoot 'shell\ARKO95.MissionControl.ps1'
$runnerPath = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95MissionControl.ps1'
$policyPath = Join-Path $ProjectRoot 'config\mission-control.json'

foreach ($path in @($modulePath,$operationsModulePath,$dashboardPath,$runnerPath)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse errors in ${path}: $($errors -join '; ')" }
}

Import-Module $modulePath -Force
Import-Module $operationsModulePath -Force
$policy = Get-Arko95MissionControlPolicy -ProjectRoot $ProjectRoot
$operationsPolicy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
$expectedStages = @('intake','decompose','route_delegate','execute','verify','persist_learn','notify_present')
if ((@($policy.stages | ForEach-Object { [string]$_.id }) -join '|') -cne ($expectedStages -join '|')) { throw 'The seven-stage mission path changed.' }
if ($policy.maximum_open_missions -ne 1 -or $policy.default_effect -ne 'proposal_only') { throw 'Mission Control lost its one-open-mission or proposal-default boundary.' }
$compiledIds = @($operationsPolicy.automatic_capabilities | ForEach-Object { [string]$_.id } | Sort-Object)
if ((@($policy.allowed_operations_capabilities | Sort-Object) -join '|') -cne ($compiledIds -join '|') -or $compiledIds.Count -ne 5) { throw 'Mission Control did not derive the exact compiled Operations VP capabilities.' }
$rawMissionPolicy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json -DateKind String
foreach ($redundantProperty in @('allowed_operations_capabilities','adapters','sensor_acceptance')) {
    if ($null -ne $rawMissionPolicy.PSObject.Properties[$redundantProperty]) { throw "Mission Control retained duplicated '$redundantProperty' policy state." }
}
if ($null -ne (Get-Command Add-Arko95MissionStageTransitionUnlocked -ErrorAction SilentlyContinue)) { throw 'The raw mission transition primitive was exported.' }

$fixtureName = 'test-mission-control-' + [guid]::NewGuid().ToString('N')
$fixtureContainer = Join-Path (Join-Path $ProjectRoot 'state') $fixtureName
$fixtureProjectRoot = Join-Path $fixtureContainer 'project'
$fixtureConfig = Join-Path $fixtureProjectRoot 'config'
$fixtureRoot = Join-Path $fixtureProjectRoot 'state\mission-control'
$operationsRoot = Join-Path $fixtureProjectRoot 'state\operations'
$tamperRoot = Join-Path $fixtureProjectRoot 'state\tamper'

try {
    New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null
    foreach ($configName in @('connector-registry.json','delegation-roster.json','mission-control.json','operations-vp.json')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot ('config\' + $configName)) -Destination (Join-Path $fixtureConfig $configName) -Force
    }
    $fixtureOperationsPolicyPath = Join-Path $fixtureConfig 'operations-vp.json'
    $fixtureOperationsPolicy = Get-Content -Raw -LiteralPath $fixtureOperationsPolicyPath | ConvertFrom-Json -DateKind String
    $fixtureOperationsPolicy.resource_guard.maximum_cpu_percent = 101
    $fixtureOperationsPolicy.resource_guard.minimum_free_memory_gb = 0
    $fixtureOperationsPolicy.resource_guard.minimum_free_disk_gb = 0
    [System.IO.File]::WriteAllText($fixtureOperationsPolicyPath,($fixtureOperationsPolicy | ConvertTo-Json -Depth 24),[System.Text.UTF8Encoding]::new($false))

    $credentialBlocked = $false
    try { New-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -Objective 'password=example-only' | Out-Null } catch { $credentialBlocked = $true }
    if (-not $credentialBlocked) { throw 'Credential-like mission text was accepted.' }

    $criterion = 'The linked local duty is complete and independently evidenced.'
    $mission = New-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -Objective 'Exercise the bounded whole-team mission path.' -Mode Forge -SuccessCriteria @($criterion)
    if ($mission.Stage -ne 'intake' -or $mission.Version -ne 1 -or $mission.ObjectiveHash -notmatch '^[a-f0-9]{64}$') { throw 'Mission Intake receipt is incomplete.' }

    $secondBlocked = $false
    try { New-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -Objective 'This second mission must remain blocked.' | Out-Null } catch { $secondBlocked = $true }
    if (-not $secondBlocked) { throw 'The one-open-mission cap failed.' }

    $staleBlocked = $false
    try { Start-Arko95MissionPlan -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 99 | Out-Null } catch { $staleBlocked = $true }
    if (-not $staleBlocked) { throw 'A stale mission version was accepted.' }

    $skipBlocked = $false
    try { Add-Arko95MissionDuty -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -OperationsStateRoot $operationsRoot -MissionId $mission.MissionId -ExpectedVersion 1 -Capability 'observe.system_health' | Out-Null } catch { $skipBlocked = $true }
    if (-not $skipBlocked) { throw 'Execute was reachable before Decompose and Route.' }

    $planned = Start-Arko95MissionPlan -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 1
    if ($planned.Stage -ne 'route_delegate' -or $planned.Version -ne 3 -or $planned.DelegationReceipt -notmatch '^[a-f0-9]{64}$' -or $planned.SpecialistCount -ne 3) {
        throw 'The bounded team plan did not reach Route & Delegate with a valid receipt.'
    }

    $unknownCapabilityBlocked = $false
    try { Add-Arko95MissionDuty -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -OperationsStateRoot $operationsRoot -MissionId $mission.MissionId -ExpectedVersion 3 -Capability 'openclaw.system_access' | Out-Null } catch { $unknownCapabilityBlocked = $true }
    if (-not $unknownCapabilityBlocked) { throw 'A non-compiled capability reached the execution broker.' }

    $queued = Add-Arko95MissionDuty -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -OperationsStateRoot $operationsRoot -MissionId $mission.MissionId -ExpectedVersion 3 -Capability 'observe.system_health'
    if ($queued.Stage -ne 'execute' -or $queued.Version -ne 4 -or $queued.DutyStatus -ne 'pending') { throw 'The compiled local duty was not linked to Execute.' }

    $earlySyncBlocked = $false
    try { Sync-Arko95MissionExecution -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -OperationsStateRoot $operationsRoot -MissionId $mission.MissionId -ExpectedVersion 4 | Out-Null } catch { $earlySyncBlocked = $true }
    if (-not $earlySyncBlocked) { throw 'An incomplete duty advanced to Verify.' }

    $ack = 'I authorize bounded R0/R1 ARKO-95 operations'
    $null = Enable-Arko95Operations -ProjectRoot $fixtureProjectRoot -StateRoot $operationsRoot -Acknowledgement $ack
    $completed = $false
    foreach ($attempt in 1..20) {
        $cycle = Invoke-Arko95OperationsCycle -ProjectRoot $fixtureProjectRoot -StateRoot $operationsRoot
        $opsPaths = Get-Arko95OperationsPaths -ProjectRoot $fixtureProjectRoot -StateRoot $operationsRoot
        foreach ($file in Get-ChildItem -LiteralPath $opsPaths.Completed -File -Filter 'duty-*.json' -ErrorAction SilentlyContinue) {
            $duty = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json -DateKind String
            if ($duty.duty_id -eq $queued.DutyId) { $completed = $true; break }
        }
        if ($completed) { break }
        Start-Sleep -Milliseconds 750
    }
    if (-not $completed) { throw 'The linked test duty did not complete inside twenty bounded cycles.' }

    $linked = Sync-Arko95MissionExecution -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -OperationsStateRoot $operationsRoot -MissionId $mission.MissionId -ExpectedVersion 4
    if ($linked.Stage -ne 'verify' -or $linked.Version -ne 5 -or $linked.ReviewReceipt -notmatch '^[a-f0-9]{64}$') { throw 'Completed duty evidence did not reach Verify.' }

    $selfVerifyBlocked = $false
    try {
        Confirm-Arko95MissionVerification -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 5 -VerifierId 'openclaw_companion' -Result pass -Checks @([pscustomobject]@{criterion=$criterion;status='pass';evidence_sha256=@($linked.ReviewReceipt)}) | Out-Null
    } catch { $selfVerifyBlocked = $true }
    if (-not $selfVerifyBlocked) { throw 'OpenClaw was accepted as an independent verifier.' }

    $missingEvidenceBlocked = $false
    try {
        Confirm-Arko95MissionVerification -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 5 -VerifierId 'independent-test-verifier' -Result pass -Checks @([pscustomobject]@{criterion=$criterion;status='pass';evidence_sha256=@()}) | Out-Null
    } catch { $missingEvidenceBlocked = $true }
    if (-not $missingEvidenceBlocked) { throw 'A passing verification check without evidence was accepted.' }

    $verified = Confirm-Arko95MissionVerification -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 5 -VerifierId 'independent-test-verifier' -Result pass -Checks @([pscustomobject]@{criterion=$criterion;status='pass';evidence_sha256=@($linked.ReviewReceipt)})
    if ($verified.Stage -ne 'persist_learn' -or $verified.Version -ne 6 -or $verified.VerificationReceipt -notmatch '^[a-f0-9]{64}$') { throw 'Independent verification did not reach Persist & Learn.' }

    $complete = Complete-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $mission.MissionId -ExpectedVersion 6 -Outcome 'The bounded local duty completed and its linked evidence passed the mission criterion.' -Unresolved @('External connector and sensor capabilities remain outside this mission.') -NextOwnerDecision 'Choose whether a new bounded mission is warranted.'
    if ($complete.Stage -ne 'notify_present' -or $complete.Status -ne 'complete' -or $complete.ExternalNotificationSent -ne $false -or -not (Test-Path -LiteralPath $complete.PresentationPath)) {
        throw 'Notify & Present did not remain local, complete, and evidenced.'
    }

    $status = Get-Arko95MissionControlStatus -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot
    if (-not $status.ChainValid -or $status.EventCount -ne 7 -or $status.OpenMissionCount -ne 0 -or $status.Missions[0].status -ne 'complete') {
        throw 'Mission projection was not rebuilt correctly from seven events.'
    }
    if ($status.Missions[0].objective_sha256 -cne $mission.ObjectiveHash) { throw 'The immutable objective digest drifted.' }

    $next = New-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -Objective 'Prove the completed mission released the single-open slot.'
    $aborted = Stop-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $fixtureRoot -MissionId $next.MissionId -ExpectedVersion 1 -Action Abort -Reason 'test_cleanup'
    if ($aborted.Status -ne 'aborted') { throw 'Mission abort did not preserve a terminal receipt.' }

    New-Item -ItemType Directory -Path $tamperRoot -Force | Out-Null
    $sourceEvents = Join-Path $fixtureRoot 'events.jsonl'
    $tamperEvents = Join-Path $tamperRoot 'events.jsonl'
    Copy-Item -LiteralPath $sourceEvents -Destination $tamperEvents -Force
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadLines($tamperEvents)) { $lines.Add($line) }
    $lines[1] = $lines[1].Replace('max_parallel_specialists', 'max_parallel_intruders')
    [System.IO.File]::WriteAllLines($tamperEvents,$lines,[System.Text.UTF8Encoding]::new($false))
    $tamper = Test-Arko95MissionControlChain -ProjectRoot $fixtureProjectRoot -StateRoot $tamperRoot
    if ($tamper.Valid) { throw 'A modified mission event survived chain verification.' }

    $dashboardOutput = & pwsh.exe -NoLogo -NoProfile -STA -File $dashboardPath -ProjectRoot $ProjectRoot -TestMode
    $dashboard = $dashboardOutput | ConvertFrom-Json
    if (-not $dashboard.ok -or -not $dashboard.xaml_loaded -or $dashboard.stage_count -ne 7 -or $dashboard.openclaw_effect -ne 'proposal_only' -or $dashboard.operations_capability_count -ne 5 -or -not $dashboard.stop_control_ready -or -not $dashboard.adapter_refresh_control_ready -or $dashboard.adapter_count -ne 4 -or $dashboard.adapter_authority -ne 'none' -or $dashboard.decision_learning_mode -ne 'shadow_learning' -or $dashboard.exploration_cap_percent -ne 25 -or $dashboard.projection_is_authority -ne $false -or $dashboard.unified_tool_count -ne 13 -or $dashboard.unified_tool_authority -ne 'none') {
        throw 'Mission Control WPF smoke test failed.'
    }

    [pscustomobject]@{
        ok = $true
        stages = 7
        replay_source_of_truth = $true
        mission_events = $status.EventCount
        objective_immutable = $true
        one_open_mission = 'verified'
        stale_version_rejection = 'verified'
        stage_skip_rejection = 'verified'
        compiled_execution_only = 'verified'
        independent_verification = 'verified'
        local_presentation_only = 'verified'
        openclaw_authority = 'none'
        ai_adapter_count = 4
        unified_tool_count = 13
        decision_learning = 'shadow_only_25_percent_cap'
        canonical_policy_sources = 'verified'
        tamper_detection = 'verified'
        dashboard = 'loaded'
    } | ConvertTo-Json -Depth 6
}
finally {
    foreach ($path in @($fixtureContainer)) {
        $full = [System.IO.Path]::GetFullPath($path)
        $stateRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'state')).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($stateRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a test path outside project state.' }
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
    }
}
