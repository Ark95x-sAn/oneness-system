[CmdletBinding()]
param([string]$ProjectRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$modulePath = Join-Path $ProjectRoot 'shell\Arko95.Operations.psm1'
$runnerPath = Join-Path $ProjectRoot 'scripts\Invoke-ARKO95OperationsVP.ps1'
$installerPath = Join-Path $ProjectRoot 'scripts\Install-ARKO95OperationsVP.ps1'
$connectorRegistryPath = Join-Path $ProjectRoot 'config\connector-registry.json'

foreach ($path in @($modulePath,$runnerPath,$installerPath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell parse errors in ${path}: $($errors -join '; ')" }
}
$installerSource=Get-Content -Raw -LiteralPath $installerPath
if ($installerSource -match '-notlike' -or $installerSource -notmatch 'Test-Arko95ScheduledTaskOwnership' -or $installerSource -notmatch '\-ceq \$ExpectedArguments') { throw 'Scheduled-task ownership is not matched exactly.' }

$fixtureRoot = Join-Path $ProjectRoot ('state\test-operations-project-{0}' -f [guid]::NewGuid().ToString('N'))
$fixtureConfig = Join-Path $fixtureRoot 'config'
$fixtureState = Join-Path $fixtureRoot 'state\operations'
New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null

try {
    $policy = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'config\operations-vp.json') | ConvertFrom-Json -DateKind String
    $policy.resource_guard.maximum_cpu_percent = 99
    $policy.resource_guard.minimum_free_memory_gb = 0.1
    $policy.resource_guard.minimum_free_disk_gb = 0.1
    [System.IO.File]::WriteAllText((Join-Path $fixtureConfig 'operations-vp.json'),($policy | ConvertTo-Json -Depth 24),[System.Text.UTF8Encoding]::new($false))

    Import-Module $modulePath -Force
    $before = Get-Arko95OperationsStatus -ProjectRoot $fixtureRoot
    if ($before.Initialized) { throw 'Fixture unexpectedly began initialized.' }

    $initialized = Initialize-Arko95Operations -ProjectRoot $fixtureRoot
    if (-not $initialized.Initialized -or $initialized.DesiredState -ne 'paused' -or -not $initialized.KillLatched -or $initialized.CircuitState -ne 'open') {
        throw 'Initialization did not fail closed.'
    }
    $chain = Test-Arko95OperationsReceiptChain -ProjectRoot $fixtureRoot
    if (-not $chain.Valid -or $chain.EventCount -lt 1) { throw 'Initialization receipt chain is invalid.' }

    $wrongAckBlocked = $false
    try { Enable-Arko95Operations -ProjectRoot $fixtureRoot -Acknowledgement 'yes' | Out-Null } catch { $wrongAckBlocked = $true }
    if (-not $wrongAckBlocked) { throw 'Operations enabled without the exact owner acknowledgement.' }

    $enabled = Enable-Arko95Operations -ProjectRoot $fixtureRoot -Acknowledgement 'I authorize bounded R0/R1 ARKO-95 operations'
    if ($enabled.DesiredState -ne 'running' -or $enabled.KillLatched -or $enabled.LeaseStatus -ne 'active' -or -not $enabled.LeaseTemporalValid) { throw 'Bounded lease did not enable correctly.' }

    $connectorRegistry = Get-Content -Raw -LiteralPath $connectorRegistryPath | ConvertFrom-Json -DateKind String
    $fixturePaths = Get-Arko95OperationsPaths -ProjectRoot $fixtureRoot
    $leaseDocument = Get-Content -Raw -LiteralPath $fixturePaths.Lease | ConvertFrom-Json -DateKind String
    if ($leaseDocument.renewal_mode -ne 'absolute_owner_grant' -or [string]$leaseDocument.absolute_not_after -cne [string]$leaseDocument.expires_at) {
        throw 'The Operations VP lease is not absolutely bounded.'
    }
    $heartbeatDocument=Get-Content -Raw -LiteralPath $fixturePaths.Heartbeat|ConvertFrom-Json -DateKind String
    $heartbeatOriginal=$heartbeatDocument|ConvertTo-Json -Depth 24
    $heartbeatDocument.timestamp=[DateTimeOffset]::UtcNow.AddDays(1).ToString('o')
    [IO.File]::WriteAllText($fixturePaths.Heartbeat,($heartbeatDocument|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $futureHeartbeatStatus=Get-Arko95OperationsStatus -ProjectRoot $fixtureRoot
    if(-not $futureHeartbeatStatus.HeartbeatFuture -or -not $futureHeartbeatStatus.HeartbeatStale -or $futureHeartbeatStatus.Ready){ throw 'A future-dated heartbeat was accepted as fresh.' }
    [IO.File]::WriteAllText($fixturePaths.Heartbeat,$heartbeatOriginal,[Text.UTF8Encoding]::new($false))
    $expectedAutomaticCapabilities = @($policy.automatic_capabilities | ForEach-Object { [string]$_.id } | Sort-Object)
    if ((@($leaseDocument.allowed_capabilities | Sort-Object) -join '|') -ne ($expectedAutomaticCapabilities -join '|')) {
        throw 'The Operations VP lease contains capabilities outside the compiled R0/R1 policy.'
    }
    foreach ($connector in @($connectorRegistry.connectors)) {
        if ([string]$connector.id -in @($leaseDocument.allowed_capabilities)) { throw "Connector $($connector.id) entered the Operations VP lease." }
        $connectorBlocked = $false
        try { New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability ([string]$connector.id) -IdempotencyKey ('connector-block-' + [string]$connector.id) | Out-Null } catch { $connectorBlocked = $true }
        if (-not $connectorBlocked) { throw "Connector $($connector.id) entered the unattended duty queue." }
    }

    $unknownBlocked = $false
    try { New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability 'shell.anything' -IdempotencyKey 'unknown-capability' | Out-Null } catch { $unknownBlocked = $true }
    if (-not $unknownBlocked) { throw 'Unknown capability entered the queue.' }

    $escapeBlocked = $false
    try { Initialize-Arko95Operations -ProjectRoot $fixtureRoot -StateRoot (Join-Path $fixtureRoot 'escape') | Out-Null } catch { $escapeBlocked = $true }
    if (-not $escapeBlocked) { throw 'Operations state escaped the fixture state directory.' }

    $first = New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability 'observe.system_health' -IdempotencyKey 'manual-health' -Parameters ([ordered]@{}) -Priority 2
    $duplicate = New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability 'observe.system_health' -IdempotencyKey 'manual-health' -Parameters ([ordered]@{}) -Priority 2
    if (-not $first.Created -or $duplicate.Created -or $first.Duty.duty_id -ne $duplicate.Duty.duty_id) { throw 'Duty idempotency failed.' }
    $changedDuplicateBlocked = $false
    try { New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability 'audit.receipt_chain' -IdempotencyKey 'manual-health' | Out-Null } catch { $changedDuplicateBlocked = $true }
    if (-not $changedDuplicateBlocked) { throw 'Changed request reused an idempotency key.' }

    $cycleOne = Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot
    if ($cycleOne.Status -ne 'completed' -or @($cycleOne.Processed).Count -ne 3) { throw 'First Operations VP cycle did not process the bounded three-duty cap.' }
    $cycleTwo = Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot
    if ($cycleTwo.Status -ne 'completed' -or @($cycleTwo.Processed).Count -lt 1) { throw 'Second Operations VP cycle did not finish remaining work.' }

    $leaseAfterCycles = Get-Content -Raw -LiteralPath $fixturePaths.Lease | ConvertFrom-Json -DateKind String
    if ([string]$leaseAfterCycles.absolute_not_after -cne [string]$leaseDocument.absolute_not_after -or [string]$leaseAfterCycles.expires_at -cne [string]$leaseDocument.expires_at) {
        throw 'A healthy Operations VP cycle extended the absolute owner lease.'
    }

    $expiredAt=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
    $leaseAfterCycles.expires_at=$expiredAt
    $leaseAfterCycles.absolute_not_after=$expiredAt
    [IO.File]::WriteAllText($fixturePaths.Lease,($leaseAfterCycles|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    if ((Get-Arko95OperationsStatus -ProjectRoot $fixtureRoot).Ready) { throw 'Expired lease still reported Operations VP ready.' }
    $expiryBlocked=$false
    try { Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot | Out-Null } catch { $expiryBlocked=$true }
    if (-not $expiryBlocked) { throw 'Expired lease did not stop the Operations VP cycle.' }
    $null=Enable-Arko95Operations -ProjectRoot $fixtureRoot -Acknowledgement 'I authorize bounded R0/R1 ARKO-95 operations'

    $budgetLease=Get-Content -Raw -LiteralPath $fixturePaths.Lease | ConvertFrom-Json -DateKind String
    $budgetLease.invocations_today=[int]$budgetLease.max_invocations_per_day
    [IO.File]::WriteAllText($fixturePaths.Lease,($budgetLease|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $completedBeforeBudget=@(Get-ChildItem -LiteralPath $fixturePaths.Completed -Filter '*.json' -File).Count
    $null=New-Arko95OperationsDuty -ProjectRoot $fixtureRoot -Capability 'observe.system_health' -IdempotencyKey 'budget-exhaustion-proof' -Parameters ([ordered]@{}) -Priority 0
    $budgetBlocked=$false
    try { Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot | Out-Null } catch { $budgetBlocked=$true }
    if (-not $budgetBlocked) { throw 'Exhausted invocation budget did not stop before execution.' }
    if (@(Get-ChildItem -LiteralPath $fixturePaths.Completed -Filter '*.json' -File).Count -ne $completedBeforeBudget) { throw 'A duty executed after the daily invocation budget was exhausted.' }
    $null=Enable-Arko95Operations -ProjectRoot $fixtureRoot -Acknowledgement 'I authorize bounded R0/R1 ARKO-95 operations'

    $runwayLease=Get-Content -Raw -LiteralPath $fixturePaths.Lease|ConvertFrom-Json -DateKind String
    $shortDeadline=[DateTimeOffset]::UtcNow.AddSeconds(5).ToString('o')
    $runwayLease.expires_at=$shortDeadline
    $runwayLease.absolute_not_after=$shortDeadline
    [IO.File]::WriteAllText($fixturePaths.Lease,($runwayLease|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $completedBeforeRunway=@(Get-ChildItem -LiteralPath $fixturePaths.Completed -Filter '*.json' -File).Count
    $runwayCycle=Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot
    if($runwayCycle.Status -ne 'circuit_open' -or @(Get-ChildItem -LiteralPath $fixturePaths.Completed -Filter '*.json' -File).Count -ne $completedBeforeRunway){ throw 'A duty effect was allowed without enough absolute lease runway.' }
    $null=Enable-Arko95Operations -ProjectRoot $fixtureRoot -Acknowledgement 'I authorize bounded R0/R1 ARKO-95 operations'

    $paths = Get-Arko95OperationsPaths -ProjectRoot $fixtureRoot
    if (@(Get-ChildItem -LiteralPath $paths.Working -Filter '*.json' -File).Count -ne 0) { throw 'A completed cycle left a claimed duty behind.' }
    $completedFiles = @(Get-ChildItem -LiteralPath $paths.Completed -Filter '*.json' -File)
    if ($completedFiles.Count -lt 4) { throw 'Expected verified duty records were not completed.' }
    foreach ($completedFile in $completedFiles) {
        $duty = Get-Content -Raw -LiteralPath $completedFile.FullName | ConvertFrom-Json -DateKind String
        if ($duty.status -ne 'verified' -or -not $duty.parent_final_judgment_required) { throw "Completed duty lacks verified parent-owned status: $($duty.duty_id)" }
        $review = Get-Content -Raw -LiteralPath $duty.review_path | ConvertFrom-Json -DateKind String
        if ($review.decision -ne 'verified' -or @($review.reviews).Count -ne 3 -or @($review.reviews | Where-Object { -not $_.passed }).Count -ne 0) {
            throw "Review team did not unanimously verify duty $($duty.duty_id)."
        }
    }
    $chainBeforeTamper = Test-Arko95OperationsReceiptChain -ProjectRoot $fixtureRoot
    if (-not $chainBeforeTamper.Valid -or $chainBeforeTamper.EventCount -lt $completedFiles.Count) { throw 'Receipt chain failed after verified duties.' }

    $receiptLines = @(Get-Content -LiteralPath $paths.Receipts)
    $receiptLines[0] = $receiptLines[0] -replace 'operations_initialized','operations_modified'
    [System.IO.File]::WriteAllLines($paths.Receipts,$receiptLines,[System.Text.UTF8Encoding]::new($false))
    if ((Test-Arko95OperationsReceiptChain -ProjectRoot $fixtureRoot).Valid) { throw 'Receipt tampering was not detected.' }
    $tamperCycleBlocked = $false
    try { Invoke-Arko95OperationsCycle -ProjectRoot $fixtureRoot | Out-Null } catch { $tamperCycleBlocked = $true }
    if (-not $tamperCycleBlocked) { throw 'A cycle continued after receipt tampering.' }
    $faulted = Get-Arko95OperationsStatus -ProjectRoot $fixtureRoot
    if (-not $faulted.KillLatched -or $faulted.CircuitState -ne 'open' -or $faulted.Ready) { throw 'Receipt tampering did not latch the circuit open.' }

    [pscustomobject]@{
        ok = $true
        parsed_files = 3
        capabilities = @($policy.automatic_capabilities | ForEach-Object id)
        cycles_verified = 2
        completed_duties = $completedFiles.Count
        reviewers_per_duty = 3
        receipt_chain_before_tamper = 'verified'
        tamper_detection = 'verified'
        kill_latch = 'verified'
        path_boundary = 'verified'
        authority = 'R0_R1_enumerated_only'
        connector_ids_rejected = @($connectorRegistry.connectors).Count
        lease_capability_count = @($leaseDocument.allowed_capabilities).Count
        lease_absolute_expiry = 'verified'
        lease_sliding_renewal = 'disabled'
        pre_effect_invocation_budget = 'verified'
        pre_effect_lease_runway = 'verified'
        future_heartbeat_rejection = 'verified'
        exact_task_ownership = 'verified'
    } | ConvertTo-Json -Depth 8
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
