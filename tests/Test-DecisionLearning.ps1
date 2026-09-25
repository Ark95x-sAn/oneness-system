[CmdletBinding()]
param([string]$ProjectRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

$learningModulePath = Join-Path $ProjectRoot 'shell\Arko95.DecisionLearning.psm1'
$missionModulePath = Join-Path $ProjectRoot 'shell\Arko95.MissionControl.psm1'
$runnerPath = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95DecisionLearning.ps1'
foreach ($path in @($learningModulePath,$runnerPath)) {
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse errors in ${path}: $($errors -join '; ')" }
}

Import-Module $missionModulePath -Force
Import-Module $learningModulePath -Force

$policy = Get-Arko95DecisionLearningPolicy -ProjectRoot $ProjectRoot
if ($policy.mode -ne 'shadow_learning' -or $policy.default_effect -ne 'proposal_only' -or $policy.execution_authority -ne 'operations_vp_only') { throw 'Decision Learning escaped shadow/proposal/Operations-only boundaries.' }
if ($policy.credit_budget.exploration_cap_percent -ne 25 -or $policy.credit_budget.protected_execution_evidence_percent -ne 75) { throw 'The 25/75 credit boundary changed.' }
if ((@($policy.record_kinds | ForEach-Object { [string]$_.id }) -join '|') -cne 'observation|inference|projection|decision_proposal|outcome|lesson_candidate') { throw 'The typed compounding pipeline changed.' }
if ((@($policy.adapters | ForEach-Object { [string]$_.id }) -join '|') -cne 'openclaw_companion|microsoft_copilot|chatgpt|codex') { throw 'The four adapter slots changed.' }
foreach ($adapter in @($policy.adapters)) {
    if ($adapter.effect -ne 'proposal_only' -or $adapter.may_write_mission_events -ne $false -or $adapter.may_invoke_operations -ne $false -or $adapter.may_approve -ne $false -or $adapter.may_promote_learning -ne $false) {
        throw "Adapter $($adapter.id) gained authority."
    }
}
if ($null -ne (Get-Command Add-Arko95LearningEventUnlocked -ErrorAction SilentlyContinue)) { throw 'The raw Decision Learning append primitive was exported.' }

$fixtureName = 'test-decision-learning-' + [guid]::NewGuid().ToString('N')
$fixtureContainer = Join-Path (Join-Path $ProjectRoot 'state') $fixtureName
$fixtureProjectRoot = Join-Path $fixtureContainer 'project'
$fixtureConfig = Join-Path $fixtureProjectRoot 'config'
$missionStateRoot = Join-Path $fixtureProjectRoot 'state\mission-control'
$learningStateRoot = Join-Path $fixtureProjectRoot 'state\decision-learning'
$tamperStateRoot = Join-Path $fixtureProjectRoot 'state\decision-learning-tamper'

try {
    New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null
    foreach ($configName in @('connector-registry.json','delegation-roster.json','mission-control.json','operations-vp.json','decision-learning.json','pc-binding.json')) {
        $source = Join-Path $ProjectRoot ('config\' + $configName)
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $fixtureConfig $configName) -Force }
    }

    $mission = New-Arko95Mission -ProjectRoot $fixtureProjectRoot -StateRoot $missionStateRoot -Objective 'Exercise the separated ARKO-95 decision and learning pipeline.' -Mode Forge -SuccessCriteria @('The learning ledger stays bounded, replayable, and non-executable.')

    $wrongObjectiveBlocked = $false
    try { New-Arko95DecisionCycle -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -MissionId $mission.MissionId -ObjectiveHash ('f' * 64) | Out-Null } catch { $wrongObjectiveBlocked = $true }
    if (-not $wrongObjectiveBlocked) { throw 'A Decision Learning cycle accepted the wrong mission objective digest.' }

    $cycle = New-Arko95DecisionCycle -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -MissionId $mission.MissionId -ObjectiveHash $mission.ObjectiveHash -TotalCredits 100
    if ($cycle.Version -ne 1 -or $cycle.ExplorationCapCredits -ne 25 -or $cycle.Effect -ne 'proposal_only') { throw 'Decision Learning cycle opening did not seal the 25-credit shadow boundary.' }

    $secondCycleBlocked = $false
    try { New-Arko95DecisionCycle -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -MissionId $mission.MissionId -ObjectiveHash $mission.ObjectiveHash | Out-Null } catch { $secondCycleBlocked = $true }
    if (-not $secondCycleBlocked) { throw 'The one-open-cycle invariant failed.' }

    $observation = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 1 -Kind observation -Content 'The authoritative mission is active at Intake.' -ProducerId 'signal-scout' -SourceReference ('mission:' + $mission.MissionId) -Confidence 100 -CreditCost 5
    if ($observation.Version -ne 2 -or $observation.ControlEffect -ne 'none') { throw 'Observation record was not sealed as inert data.' }

    $missingParentBlocked = $false
    try { Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 2 -Kind inference -Content 'This must fail without a fact parent.' -ProducerId 'path-architect' -CreditCost 1 | Out-Null } catch { $missingParentBlocked = $true }
    if (-not $missingParentBlocked) { throw 'An inference without an observation parent was accepted.' }

    $inference = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 2 -Kind inference -Content 'A bounded local receipt audit is the lowest-risk useful next check.' -ProducerId 'path-architect' -ParentRecordIds @($observation.RecordId) -Confidence 80 -Uncertainty 'The operation has not run yet.' -CreditCost 8
    $projection = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 3 -Kind projection -Content 'If the receipt chain remains valid, the audit should complete without an external effect.' -ProducerId 'forecast-lane' -ParentRecordIds @($inference.RecordId) -Confidence 70 -Uncertainty 'This is a forecast, not an observed result.' -CreditCost 8
    $decision = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 4 -Kind decision_proposal -Content 'Propose the compiled audit.receipt_chain duty for separate Operations VP authorization.' -ProducerId 'parent-integrator' -ParentRecordIds @($projection.RecordId) -SuggestedOperationsCapability 'audit.receipt_chain' -Confidence 75 -Uncertainty 'This proposal does not invoke the duty.' -CreditCost 8
    if ($decision.Version -ne 5 -or $decision.CreditClass -ne 'exploration') { throw 'Decision proposal did not remain an exploration record.' }

    $fakeReceipt = ('a' * 64)
    $outcome = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 5 -Kind outcome -Content 'A separately authorized bounded receipt audit returned a valid local result.' -ProducerId 'receipt-linker' -ParentRecordIds @($decision.RecordId) -SourceReference 'operations-receipt:test-only' -EvidenceSha256 @($fakeReceipt) -Confidence 100 -CreditCost 10
    $lesson = Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 6 -Kind lesson_candidate -Content 'When the mission chain is valid, prefer the compiled receipt audit before broader troubleshooting.' -ProducerId 'receipt-archivist' -ParentRecordIds @($outcome.RecordId) -Confidence 70 -Uncertainty 'Candidate applies only to this bounded local pattern.' -CreditCost 1
    if ($lesson.Version -ne 7 -or $lesson.PromotionState -ne 'proposed_only') { throw 'Lesson candidate escaped proposed-only state.' }

    $overBudgetBlocked = $false
    try { Add-Arko95DecisionRecord -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 7 -Kind inference -Content 'This extra exploration credit must be rejected.' -ProducerId 'budget-test' -ParentRecordIds @($observation.RecordId) -CreditCost 1 | Out-Null } catch { $overBudgetBlocked = $true }
    if (-not $overBudgetBlocked) { throw 'The 25 percent exploration ceiling failed.' }

    $staleBlocked = $false
    try { Set-Arko95LessonCandidateReview -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 6 -CandidateRecordId $lesson.RecordId -ReviewState owner_approved_reference -OwnerId 'local-owner' | Out-Null } catch { $staleBlocked = $true }
    if (-not $staleBlocked) { throw 'A stale Decision Learning version was accepted.' }

    $review = Set-Arko95LessonCandidateReview -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 7 -CandidateRecordId $lesson.RecordId -ReviewState owner_approved_reference -OwnerId 'local-owner' -Reason 'Useful as a reference only.'
    if ($review.Version -ne 8 -or $review.PolicyChange -ne $false -or $review.MemoryRewrite -ne $false) { throw 'Owner lesson review gained policy or memory rewrite authority.' }

    $closed = Close-Arko95DecisionCycle -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -MissionStateRoot $missionStateRoot -CycleId $cycle.CycleId -ExpectedVersion 8 -ParentIntegratorId 'arko95-parent'
    if ($closed.Status -ne 'closed' -or $closed.Version -ne 9 -or $closed.ExplorationUsed -ne 25 -or $closed.ExternalNotificationSent -ne $false) { throw 'Decision Learning cycle closure is incomplete or unsafe.' }

    $status = Get-Arko95DecisionLearningStatus -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot
    if (-not $status.ChainValid -or $status.EventCount -ne 9 -or $status.OpenCycleCount -ne 0 -or $status.Cycles[0].records.Count -ne 6) { throw 'Decision Learning replay did not reproduce the completed compound pipeline.' }
    if ($status.Cycles[0].exploration_used -ne 25 -or $status.Cycles[0].execution_evidence_used -ne 15 -or $status.Cycles[0].remaining_credits -ne 60) { throw 'Decision Learning credit replay is incorrect.' }
    if ($status.ProjectionIsAuthority -ne $false -or $status.AdapterAuthority -ne 'none' -or @($status.Adapters).Count -ne 4) { throw 'Projection or adapter authority escaped its boundary.' }
    foreach ($adapter in @($status.Adapters)) { if ($adapter.authority -ne 'none' -or $adapter.effect -ne 'proposal_only') { throw "Adapter $($adapter.adapter_id) gained authority." } }

    $paths = Get-Arko95DecisionLearningPaths -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot
    $projectionState = Get-Content -Raw -LiteralPath $paths.Projection | ConvertFrom-Json -DateKind String
    if ($projectionState.derived_only -ne $true -or $projectionState.authority -ne 'ledger_replay_only') { throw 'The disposable projection was mistaken for authority.' }

    $now = [DateTimeOffset]::UtcNow
    $adapterReceipt = Register-Arko95AdapterObservation -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot -AdapterId chatgpt -AdapterVersion 'test-package-only' -HostOrTenant 'TEST-HOST' -SourceKind process_and_package_metadata -SourceReference 'test-only package/process observation' -Claims @('package_present','process_running') -ObservedAt $now -FreshUntil $now.AddMinutes(10) -ObservationSha256 ('b' * 64) -ConnectionState observed_present
    $adapterStatus = @(Get-Arko95AdapterFabricStatus -ProjectRoot $fixtureProjectRoot -StateRoot $learningStateRoot | Where-Object { $_.adapter_id -eq 'chatgpt' })[0]
    if ($adapterReceipt.Authority -ne 'none' -or $adapterStatus.runtime_state -ne 'observed_fresh' -or $adapterStatus.receipt_integrity_valid -ne $true) { throw 'A canonical adapter receipt was not validated correctly.' }

    New-Item -ItemType Directory -Path $tamperStateRoot -Force | Out-Null
    $tamperLedger = Join-Path $tamperStateRoot 'ledger.jsonl'
    Copy-Item -LiteralPath $paths.Ledger -Destination $tamperLedger -Force
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadLines($tamperLedger)) { $lines.Add($line) }
    $lines[1] = $lines[1].Replace('authoritative mission','forged mission')
    [System.IO.File]::WriteAllLines($tamperLedger,$lines,[System.Text.UTF8Encoding]::new($false))
    $tamper = Test-Arko95DecisionLearningChain -ProjectRoot $fixtureProjectRoot -StateRoot $tamperStateRoot
    if ($tamper.Valid) { throw 'A modified Decision Learning event survived chain verification.' }

    [pscustomobject]@{
        ok = $true
        record_kinds = 6
        adapters = 4
        adapter_authority = 'none'
        mission_binding = 'verified'
        separate_projection = 'verified'
        exploration_cap_percent = 25
        exploration_cap_enforced = 'verified'
        compound_lineage = 'verified'
        lesson_promotion = 'owner_reference_only'
        execution_authority = 'operations_vp_only'
        chain_events = $status.EventCount
        tamper_detection = 'verified'
    } | ConvertTo-Json -Depth 6
}
finally {
    $full = [System.IO.Path]::GetFullPath($fixtureContainer)
    $stateRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'state')).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($stateRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a Decision Learning fixture outside project state.' }
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}
