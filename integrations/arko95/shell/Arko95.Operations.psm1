Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$coreModule = Join-Path $PSScriptRoot 'Arko95.Core.psm1'
Import-Module $coreModule -Force

function Get-Arko95OpsProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-Arko95OpsStringHash {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-Arko95OpsObjectHash {
    param([Parameter(Mandatory)]$Value)
    $canonical = $Value | ConvertTo-Json -Compress -Depth 24
    return Get-Arko95OpsStringHash -Text $canonical
}

function Read-Arko95OpsJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int64]$MaximumBytes = 2097152
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Length -gt $MaximumBytes) { throw "Operations state file exceeds its size limit: $Path" }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Operations state cannot be read through a reparse point: $Path" }
    return Get-Content -Raw -LiteralPath $Path -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
}

function Write-Arko95OpsJsonAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    $directory = Split-Path -Parent $Path
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $target = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($target.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing to replace a reparse-point target: $Path" }
    }
    $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f ([System.IO.Path]::GetFileName($Path)), [guid]::NewGuid().ToString('N'))
    try {
        $json = $Value | ConvertTo-Json -Depth 24
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
    }
}

function Get-Arko95OperationsPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $corePaths = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = $corePaths.OperationsState }
    $scopeMarker = Join-Path $StateRoot '.scope'
    $resolvedMarker = Resolve-Arko95StateWritePath -ProjectRoot $ProjectRoot -RequestedPath $scopeMarker -DefaultPath $scopeMarker
    $root = Split-Path -Parent $resolvedMarker
    $queueRoot = Join-Path $root 'queue'
    [pscustomobject]@{
        ProjectRoot   = [System.IO.Path]::GetFullPath($ProjectRoot)
        Policy        = $corePaths.OperationsPolicy
        Root          = $root
        QueueRoot     = $queueRoot
        Pending       = Join-Path $queueRoot 'pending'
        Working       = Join-Path $queueRoot 'working'
        Completed     = Join-Path $queueRoot 'completed'
        Failed        = Join-Path $queueRoot 'failed'
        Held          = Join-Path $queueRoot 'held'
        Reports       = Join-Path $root 'reports'
        Reviews       = Join-Path $root 'reviews'
        Control       = Join-Path $root 'control.json'
        Lease         = Join-Path $root 'authority-lease.json'
        Runtime       = Join-Path $root 'runtime-state.json'
        Heartbeat     = Join-Path $root 'heartbeat.json'
        Receipts      = Join-Path $root 'receipts.jsonl'
        ChainHead     = Join-Path $root 'receipt-chain-head.json'
        LockMarker    = Join-Path $root 'worker.lock'
        LatestBrief   = Join-Path $root 'reports\latest-brief.json'
        DelegationPlan = $corePaths.LatestPlan
    }
}

function Get-Arko95OperationsPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $paths = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot
    $policy = Read-Arko95OpsJson -Path $paths.OperationsPolicy
    if ($null -eq $policy -or [int](Get-Arko95OpsProperty -InputObject $policy -Name 'schema_version' -Default 0) -ne 1) {
        throw 'The Operations VP policy is missing or unsupported.'
    }
    if ([string](Get-Arko95OpsProperty -InputObject $policy -Name 'default_effect') -ne 'deny') { throw 'Operations VP must remain default-deny.' }
    if ([string](Get-Arko95OpsProperty -InputObject $policy -Name 'authority_model') -ne 'revocable_policy_epoch') { throw 'Operations VP requires revocable policy epochs.' }

    $allowedHandlers = @('system_health_snapshot','receipt_chain_audit','delegation_receipt_verify','operations_brief','operations_workspace_maintain')
    $allowedRiskTiers = @('R0','R1')
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($capability in @($policy.automatic_capabilities)) {
        $id = [string](Get-Arko95OpsProperty -InputObject $capability -Name 'id' -Default '')
        $handler = [string](Get-Arko95OpsProperty -InputObject $capability -Name 'handler' -Default '')
        $risk = [string](Get-Arko95OpsProperty -InputObject $capability -Name 'risk_tier' -Default '')
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw 'Automatic capability identifiers must be present and unique.' }
        if ($handler -notin $allowedHandlers) { throw "Capability '$id' references a handler that is not compiled into the broker." }
        if ($risk -notin $allowedRiskTiers) { throw "Capability '$id' exceeds the automatic R0/R1 boundary." }
        if (-not [bool](Get-Arko95OpsProperty -InputObject $capability -Name 'reversible' -Default $false)) { throw "Capability '$id' must declare reversible local behavior." }
        if ([int](Get-Arko95OpsProperty -InputObject $capability -Name 'maximum_seconds' -Default 0) -lt 1) { throw "Capability '$id' has no bounded runtime." }
    }
    if ($seen.Count -lt 1) { throw 'Operations VP has no bounded automatic capabilities.' }

    foreach ($schedule in @($policy.recurring_duties)) {
        $capabilityId = [string](Get-Arko95OpsProperty -InputObject $schedule -Name 'capability' -Default '')
        if (-not $seen.Contains($capabilityId)) { throw "Recurring duty references unknown capability '$capabilityId'." }
        if ([int](Get-Arko95OpsProperty -InputObject $schedule -Name 'every_seconds' -Default 0) -lt 60) { throw 'Recurring duties may not run more often than once per minute.' }
    }
    if (@($policy.hard_denials).Count -lt 1 -or @($policy.foreground_approval_required).Count -lt 1) { throw 'Operations VP policy boundaries are incomplete.' }
    return $policy
}

function Enter-Arko95OperationsMutex {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $nameHash = (Get-Arko95OpsStringHash -Text ([System.IO.Path]::GetFullPath($ProjectRoot))).Substring(0, 24)
    $mutex = [System.Threading.Mutex]::new($false, "Local\ARKO95_OPS_$nameHash")
    $acquired = $false
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        $mutex.Dispose()
        throw 'Another ARKO-95 Operations VP cycle already owns the worker lock.'
    }
    return $mutex
}

function Exit-Arko95OperationsMutex {
    param([AllowNull()][System.Threading.Mutex]$Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

function Get-Arko95OpsReceiptChainStatus {
    param([Parameter(Mandatory)]$Paths)

    $zeroHash = '0' * 64
    $expectedPrevious = $zeroHash
    $count = 0
    $errorText = $null
    try {
        if (Test-Path -LiteralPath $Paths.Receipts -PathType Leaf) {
            $item = Get-Item -LiteralPath $Paths.Receipts -Force -ErrorAction Stop
            if ($item.Length -gt 20971520) { throw 'Receipt journal exceeds 20 MB.' }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Receipt journal is a reparse point.' }
            foreach ($line in @(Get-Content -LiteralPath $Paths.Receipts -ErrorAction Stop)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $event = $line | ConvertFrom-Json -DateKind String -ErrorAction Stop
                $savedHash = [string](Get-Arko95OpsProperty -InputObject $event -Name 'event_hash' -Default '')
                $previousHash = [string](Get-Arko95OpsProperty -InputObject $event -Name 'previous_hash' -Default '')
                if ($previousHash -cne $expectedPrevious) { throw "Receipt link mismatch at event $count." }
                $event.PSObject.Properties.Remove('event_hash')
                $computedHash = Get-Arko95OpsObjectHash -Value $event
                if ($computedHash -cne $savedHash) { throw "Receipt digest mismatch at event $count." }
                $expectedPrevious = $savedHash
                $count++
            }
        }
        $head = Read-Arko95OpsJson -Path $Paths.ChainHead
        if ($null -eq $head) { throw 'Receipt chain head is missing.' }
        if ([int](Get-Arko95OpsProperty -InputObject $head -Name 'event_count' -Default -1) -ne $count) { throw 'Receipt chain count does not match its checkpoint.' }
        if ([string](Get-Arko95OpsProperty -InputObject $head -Name 'head_hash' -Default '') -cne $expectedPrevious) { throw 'Receipt chain head hash does not match its checkpoint.' }
    }
    catch { $errorText = $_.Exception.Message }

    [pscustomobject]@{
        Valid      = [string]::IsNullOrWhiteSpace($errorText)
        EventCount = $count
        HeadHash   = $expectedPrevious
        Error      = $errorText
    }
}

function Add-Arko95OpsEvent {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$EventType,
        [string]$DutyId = '',
        $Payload = $null
    )
    $chain = Get-Arko95OpsReceiptChainStatus -Paths $Paths
    if (-not $chain.Valid) { throw "Receipt chain is invalid: $($chain.Error)" }
    $event = [ordered]@{
        schema_version = 1
        event_id        = 'event-' + [guid]::NewGuid().ToString('D')
        created_at      = [DateTimeOffset]::UtcNow.ToString('o')
        event_type      = $EventType
        duty_id         = $DutyId
        payload         = $Payload
        previous_hash   = $chain.HeadHash
    }
    $event.event_hash = Get-Arko95OpsObjectHash -Value $event
    $line = ($event | ConvertTo-Json -Compress -Depth 24) + [Environment]::NewLine
    [System.IO.File]::AppendAllText($Paths.Receipts, $line, [System.Text.UTF8Encoding]::new($false))
    Write-Arko95OpsJsonAtomic -Path $Paths.ChainHead -Value ([ordered]@{
        schema_version = 1
        event_count    = $chain.EventCount + 1
        head_hash      = $event.event_hash
        updated_at     = [DateTimeOffset]::UtcNow.ToString('o')
    })
    return [pscustomobject]$event
}

function Initialize-Arko95OperationsState {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Paths
    )
    $null = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
    foreach ($directory in @($Paths.Root,$Paths.QueueRoot,$Paths.Pending,$Paths.Working,$Paths.Completed,$Paths.Failed,$Paths.Held,$Paths.Reports,$Paths.Reviews)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        $item = Get-Item -LiteralPath $directory -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Operations directory may not be a reparse point: $directory" }
    }

    $created = $false
    if (-not (Test-Path -LiteralPath $Paths.ChainHead)) {
        Write-Arko95OpsJsonAtomic -Path $Paths.ChainHead -Value ([ordered]@{ schema_version = 1; event_count = 0; head_hash = ('0' * 64); updated_at = [DateTimeOffset]::UtcNow.ToString('o') })
        $created = $true
    }
    if (-not (Test-Path -LiteralPath $Paths.Control)) {
        Write-Arko95OpsJsonAtomic -Path $Paths.Control -Value ([ordered]@{
            schema_version = 1; desired_state = 'paused'; kill_latched = $true; reason = 'not_enabled'; policy_epoch = 0; updated_at = [DateTimeOffset]::UtcNow.ToString('o'); updated_by = 'initializer'
        })
        $created = $true
    }
    if (-not (Test-Path -LiteralPath $Paths.Runtime)) {
        Write-Arko95OpsJsonAtomic -Path $Paths.Runtime -Value ([ordered]@{
            schema_version = 1; circuit_state = 'open'; consecutive_failures = 0; cycles_completed = 0; duties_completed = 0; duties_failed = 0; last_fault = 'not_enabled'; last_cycle_at = $null; updated_at = [DateTimeOffset]::UtcNow.ToString('o')
        })
        $created = $true
    }
    if (-not (Test-Path -LiteralPath $Paths.Heartbeat)) {
        Write-Arko95OpsJsonAtomic -Path $Paths.Heartbeat -Value ([ordered]@{
            schema_version = 1; worker_instance = ''; status = 'never_started'; timestamp = $null; cycle_id = ''
        })
    }
    if ($created) { $null = Add-Arko95OpsEvent -Paths $Paths -EventType 'operations_initialized' -Payload ([ordered]@{ effect = 'local_state_only'; control = 'paused'; circuit = 'open' }) }
}

function Initialize-Arko95Operations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $mutex = $null
    try {
        $mutex = Enter-Arko95OperationsMutex -ProjectRoot $ProjectRoot
        $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        Initialize-Arko95OperationsState -ProjectRoot $ProjectRoot -Paths $paths
        return Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    }
    finally { Exit-Arko95OperationsMutex -Mutex $mutex }
}

function Test-Arko95OperationsReceiptChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    return Get-Arko95OpsReceiptChainStatus -Paths $paths
}

function Get-Arko95OpsQueueCounts {
    param([Parameter(Mandatory)]$Paths)
    [ordered]@{
        pending   = @(Get-ChildItem -LiteralPath $Paths.Pending -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        working   = @(Get-ChildItem -LiteralPath $Paths.Working -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        completed = @(Get-ChildItem -LiteralPath $Paths.Completed -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        failed    = @(Get-ChildItem -LiteralPath $Paths.Failed -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
        held      = @(Get-ChildItem -LiteralPath $Paths.Held -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    }
}

function Get-Arko95OperationsStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    if (-not (Test-Path -LiteralPath $paths.Control -PathType Leaf)) {
        return [pscustomobject]@{ Initialized = $false; Ready = $false; DesiredState = 'not_initialized'; KillLatched = $true; CircuitState = 'open'; LeaseStatus = 'missing'; Queue = [ordered]@{ pending=0;working=0;completed=0;failed=0;held=0 }; HeartbeatAgeSeconds = $null; HeartbeatStale = $true; ReceiptChainValid = $false; LastFault = 'not_initialized' }
    }
    $policy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
    $control = Read-Arko95OpsJson -Path $paths.Control
    $runtime = Read-Arko95OpsJson -Path $paths.Runtime
    $lease = Read-Arko95OpsJson -Path $paths.Lease
    $heartbeat = Read-Arko95OpsJson -Path $paths.Heartbeat
    $chain = Get-Arko95OpsReceiptChainStatus -Paths $paths
    $heartbeatAge = $null
    $heartbeatTimestamp = Get-Arko95OpsProperty -InputObject $heartbeat -Name 'timestamp'
    if (-not [string]::IsNullOrWhiteSpace([string]$heartbeatTimestamp)) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$heartbeatTimestamp, [ref]$parsed)) { $heartbeatAge = [math]::Max(0,[math]::Round(([DateTimeOffset]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds,0)) }
    }
    $staleAfter = [int]$policy.scheduler.heartbeat_stale_after_seconds
    $leaseStatus = [string](Get-Arko95OpsProperty -InputObject $lease -Name 'status' -Default 'missing')
    $desired = [string](Get-Arko95OpsProperty -InputObject $control -Name 'desired_state' -Default 'paused')
    $kill = [bool](Get-Arko95OpsProperty -InputObject $control -Name 'kill_latched' -Default $true)
    $circuit = [string](Get-Arko95OpsProperty -InputObject $runtime -Name 'circuit_state' -Default 'open')
    [pscustomobject]@{
        Initialized         = $true
        Ready               = ($desired -eq 'running' -and -not $kill -and $circuit -eq 'closed' -and $leaseStatus -eq 'active' -and $chain.Valid)
        DesiredState        = $desired
        KillLatched         = $kill
        KillReason          = [string](Get-Arko95OpsProperty -InputObject $control -Name 'reason' -Default '')
        PolicyEpoch         = [int](Get-Arko95OpsProperty -InputObject $control -Name 'policy_epoch' -Default 0)
        CircuitState        = $circuit
        LeaseStatus         = $leaseStatus
        LeaseId             = [string](Get-Arko95OpsProperty -InputObject $lease -Name 'lease_id' -Default '')
        LeaseExpiresAt      = Get-Arko95OpsProperty -InputObject $lease -Name 'expires_at'
        Queue               = Get-Arko95OpsQueueCounts -Paths $paths
        HeartbeatStatus     = [string](Get-Arko95OpsProperty -InputObject $heartbeat -Name 'status' -Default 'unknown')
        HeartbeatAgeSeconds = $heartbeatAge
        HeartbeatStale      = ($null -eq $heartbeatAge) -or ($heartbeatAge -gt $staleAfter)
        ReceiptChainValid   = $chain.Valid
        ReceiptEventCount   = $chain.EventCount
        ReceiptHeadHash     = $chain.HeadHash
        LastFault           = [string](Get-Arko95OpsProperty -InputObject $runtime -Name 'last_fault' -Default '')
        CyclesCompleted     = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'cycles_completed' -Default 0)
        DutiesCompleted     = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_completed' -Default 0)
        DutiesFailed        = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_failed' -Default 0)
    }
}

function Get-Arko95OpsCapability {
    param(
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][string]$CapabilityId
    )
    return @($Policy.automatic_capabilities | Where-Object { [string]$_.id -ceq $CapabilityId } | Select-Object -First 1)[0]
}

function Invoke-Arko95OpsTripCircuit {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$Reason,
        [string]$DutyId = '',
        [string]$FaultClass = 'runtime_fault'
    )
    $now = [DateTimeOffset]::UtcNow.ToString('o')
    $control = Read-Arko95OpsJson -Path $Paths.Control
    $runtime = Read-Arko95OpsJson -Path $Paths.Runtime
    $lease = Read-Arko95OpsJson -Path $Paths.Lease
    Write-Arko95OpsJsonAtomic -Path $Paths.Control -Value ([ordered]@{
        schema_version = 1
        desired_state  = 'paused'
        kill_latched   = $true
        reason         = $Reason
        policy_epoch   = [int](Get-Arko95OpsProperty -InputObject $control -Name 'policy_epoch' -Default 0)
        updated_at     = $now
        updated_by     = 'circuit_breaker'
  …5816 tokens truncated…ilityDefinition.risk_tier -notin @($Policy.lease.automatic_risk_tiers | ForEach-Object { [string]$_ })) { $reasons.Add('risk_tier_not_automatic') }
    if ([bool]$Duty.execution_authority) { $reasons.Add('duty_claimed_its_own_authority') }
    [pscustomobject]@{
        reviewer = 'policy_sentinel'
        phase = 'preflight'
        passed = $reasons.Count -eq 0
        reasons = $reasons.ToArray()
        checked_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Invoke-Arko95OpsPostReview {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Duty,
        [Parameter(Mandatory)]$CapabilityDefinition,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][double]$DurationSeconds,
        [Parameter(Mandatory)]$Preflight
    )
    $evidenceReasons = [Collections.Generic.List[string]]::new()
    $rootPrefix = [System.IO.Path]::GetFullPath($Paths.Root).TrimEnd('\') + '\'
    foreach ($artifactPath in @($Result.ArtifactPaths)) {
        $fullPath = [System.IO.Path]::GetFullPath([string]$artifactPath)
        if (-not $fullPath.StartsWith($rootPrefix,[System.StringComparison]::OrdinalIgnoreCase)) { $evidenceReasons.Add("artifact_outside_operations_state:$fullPath"); continue }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { $evidenceReasons.Add("artifact_missing:$fullPath"); continue }
        $item = Get-Item -LiteralPath $fullPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $evidenceReasons.Add("artifact_reparse_point:$fullPath"); continue }
        $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedHash = [string]$Result.ArtifactHashes[$fullPath]
        if ($actualHash -cne $expectedHash) { $evidenceReasons.Add("artifact_hash_mismatch:$fullPath") }
    }
    if (@($Result.ArtifactPaths).Count -lt 1) { $evidenceReasons.Add('no_artifact') }
    $evidenceReview = [pscustomobject]@{ reviewer='evidence_auditor'; phase='postcondition'; passed=$evidenceReasons.Count -eq 0; reasons=$evidenceReasons.ToArray(); checked_at=[DateTimeOffset]::UtcNow.ToString('o') }

    $reliabilityReasons = [Collections.Generic.List[string]]::new()
    if (-not [bool]$Result.Success) { $reliabilityReasons.Add('handler_reported_failure') }
    if ($DurationSeconds -gt [double]$CapabilityDefinition.maximum_seconds) { $reliabilityReasons.Add('handler_exceeded_runtime_budget') }
    if ([string]::IsNullOrWhiteSpace([string]$Duty.idempotency_key)) { $reliabilityReasons.Add('missing_idempotency_key') }
    if (-not [bool]$Result.Reversible) { $reliabilityReasons.Add('result_not_reversible') }
    $reliabilityReview = [pscustomobject]@{ reviewer='reliability_tester'; phase='postcondition'; passed=$reliabilityReasons.Count -eq 0; reasons=$reliabilityReasons.ToArray(); checked_at=[DateTimeOffset]::UtcNow.ToString('o') }
    $passed = [bool]$Preflight.passed -and [bool]$evidenceReview.passed -and [bool]$reliabilityReview.passed
    [pscustomobject]@{
        passed = $passed
        reviews = @($Preflight,$evidenceReview,$reliabilityReview)
        decision = if ($passed) { 'verified' } else { 'rejected' }
        parent_final_judgment_required = $true
    }
}

function Move-Arko95OpsDuty {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )
    $destination = Join-Path $DestinationDirectory ([System.IO.Path]::GetFileName($Source))
    [System.IO.File]::Move($Source,$destination,$true)
    return $destination
}

function Set-Arko95OpsHeartbeat {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$WorkerInstance,
        [Parameter(Mandatory)][string]$CycleId,
        [Parameter(Mandatory)][string]$Status,
        $Details = $null
    )
    Write-Arko95OpsJsonAtomic -Path $Paths.Heartbeat -Value ([ordered]@{
        schema_version = 1; worker_instance = $WorkerInstance; status = $Status; timestamp = [DateTimeOffset]::UtcNow.ToString('o'); cycle_id = $CycleId; details = $Details
    })
}

function Invoke-Arko95OperationsCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $mutex = $null
    $paths = $null
    $cycleId = 'cycle-' + [guid]::NewGuid().ToString('D')
    $workerInstance = 'worker-' + [guid]::NewGuid().ToString('D')
    $processed = [Collections.Generic.List[object]]::new()
    try {
        $mutex = Enter-Arko95OperationsMutex -ProjectRoot $ProjectRoot
        $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        Initialize-Arko95OperationsState -ProjectRoot $ProjectRoot -Paths $paths
        $policy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
        $control = Read-Arko95OpsJson -Path $paths.Control
        $runtime = Read-Arko95OpsJson -Path $paths.Runtime
        $lease = Read-Arko95OpsJson -Path $paths.Lease
        $chain = Get-Arko95OpsReceiptChainStatus -Paths $paths
        if (-not $chain.Valid) {
            Invoke-Arko95OpsTripCircuit -Paths $paths -Reason ('receipt_chain_invalid:' + $chain.Error) -FaultClass 'audit_integrity'
            throw "Receipt chain is invalid: $($chain.Error)"
        }
        if ([bool]$control.kill_latched -or [string]$control.desired_state -ne 'running' -or [string]$runtime.circuit_state -ne 'closed') {
            return [pscustomobject]@{ CycleId=$cycleId; Status='paused'; Processed=@(); Reason=[string]$control.reason; Operations=Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
        }
        if ($null -eq $lease -or [string]$lease.status -ne 'active' -or [int]$lease.policy_epoch -ne [int]$control.policy_epoch) {
            Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'lease_missing_inactive_or_epoch_mismatch' -FaultClass 'authority_failure'
            throw 'The active lease is missing, inactive, or bound to another policy epoch.'
        }
        $leaseExpiry = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$lease.expires_at,[ref]$leaseExpiry) -or $leaseExpiry -le [DateTimeOffset]::UtcNow) {
            Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'lease_expired' -FaultClass 'authority_failure'
            throw 'The Operations VP lease expired.'
        }

        $workingFiles = @(Get-ChildItem -LiteralPath $paths.Working -Filter '*.json' -File -ErrorAction SilentlyContinue)
        if ($workingFiles.Count -gt 0) {
            foreach ($workingFile in $workingFiles) {
                $duty = Read-Arko95OpsJson -Path $workingFile.FullName
                $duty.status = 'held'
                $duty.hold_reason = 'uncertain_after_worker_interruption'
                Write-Arko95OpsJsonAtomic -Path $workingFile.FullName -Value $duty
                $null = Move-Arko95OpsDuty -Source $workingFile.FullName -DestinationDirectory $paths.Held
            }
            Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'uncertain_working_duty_after_interruption' -FaultClass 'crash_recovery'
            throw 'A previously claimed duty had uncertain post-state; operations stopped for review.'
        }

        Set-Arko95OpsHeartbeat -Paths $paths -WorkerInstance $workerInstance -CycleId $cycleId -Status 'running'
        $resourceSnapshot = Get-Arko95OpsResourceSnapshot -ProjectRoot $ProjectRoot
        $admission = Test-Arko95OpsResourceAdmission -Policy $policy -Snapshot $resourceSnapshot
        if (-not $admission.Admitted) {
            Set-Arko95OpsHeartbeat -Paths $paths -WorkerInstance $workerInstance -CycleId $cycleId -Status 'resource_hold' -Details ([ordered]@{ reasons=@($admission.Reasons) })
            return [pscustomobject]@{ CycleId=$cycleId; Status='resource_hold'; Processed=@(); Reason=($admission.Reasons -join ','); Operations=Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
        }

        $scheduled = Add-Arko95OpsRecurringDuties -Paths $paths -Policy $policy
        $pending = [Collections.Generic.List[object]]::new()
        foreach ($file in @(Get-ChildItem -LiteralPath $paths.Pending -Filter '*.json' -File -ErrorAction Stop)) {
            $duty = Read-Arko95OpsJson -Path $file.FullName
            $notBeforeReady = $true
            if (-not [string]::IsNullOrWhiteSpace([string]$duty.not_before)) {
                $notBefore = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse([string]$duty.not_before,[ref]$notBefore)) { $notBeforeReady = $notBefore -le [DateTimeOffset]::UtcNow }
            }
            if ($notBeforeReady) { $pending.Add([pscustomobject]@{ Path=$file.FullName; Duty=$duty }) }
        }
        $selected = @($pending | Sort-Object @{Expression={[int]$_.Duty.priority};Ascending=$true}, @{Expression={[string]$_.Duty.created_at};Ascending=$true} | Select-Object -First ([int]$policy.scheduler.max_duties_per_cycle))
        foreach ($item in $selected) {
            $control = Read-Arko95OpsJson -Path $paths.Control
            $lease = Read-Arko95OpsJson -Path $paths.Lease
            if ([bool]$control.kill_latched -or [string]$control.desired_state -ne 'running') { break }
            $chain = Get-Arko95OpsReceiptChainStatus -Paths $paths
            if (-not $chain.Valid) {
                Invoke-Arko95OpsTripCircuit -Paths $paths -Reason ('receipt_chain_changed_during_cycle:' + $chain.Error) -DutyId ([string]$item.Duty.duty_id) -FaultClass 'audit_integrity'
                break
            }
            $duty = $item.Duty
            $capabilityDefinition = Get-Arko95OpsCapability -Policy $policy -CapabilityId ([string]$duty.capability)
            if ($null -eq $capabilityDefinition) {
                $duty.status = 'held'; $duty.hold_reason = 'unknown_capability'
                Write-Arko95OpsJsonAtomic -Path $item.Path -Value $duty
                $null = Move-Arko95OpsDuty -Source $item.Path -DestinationDirectory $paths.Held
                Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'unknown_capability_in_queue' -DutyId ([string]$duty.duty_id) -FaultClass 'policy_violation'
                break
            }
            $preflight = Invoke-Arko95OpsPreflightReview -Duty $duty -CapabilityDefinition $capabilityDefinition -Control $control -Lease $lease -Policy $policy
            if (-not $preflight.passed) {
                $duty.status = 'held'; $duty.hold_reason = 'preflight_rejected'; $duty.preflight = $preflight
                Write-Arko95OpsJsonAtomic -Path $item.Path -Value $duty
                $null = Move-Arko95OpsDuty -Source $item.Path -DestinationDirectory $paths.Held
                Invoke-Arko95OpsTripCircuit -Paths $paths -Reason ('preflight_rejected:' + ($preflight.reasons -join ',')) -DutyId ([string]$duty.duty_id) -FaultClass 'policy_violation'
                break
            }

            $workingPath = Move-Arko95OpsDuty -Source $item.Path -DestinationDirectory $paths.Working
            $duty.status = 'working'
            $duty.attempts = [int]$duty.attempts + 1
            $duty.fence_token = [int]$duty.fence_token + 1
            $duty.claimed_at = [DateTimeOffset]::UtcNow.ToString('o')
            $duty.worker_instance = $workerInstance
            $duty.lease_id = [string]$lease.lease_id
            $duty.policy_epoch = [int]$control.policy_epoch
            $duty.preflight = $preflight
            Write-Arko95OpsJsonAtomic -Path $workingPath -Value $duty
            $null = Add-Arko95OpsEvent -Paths $paths -EventType 'duty_claimed' -DutyId ([string]$duty.duty_id) -Payload ([ordered]@{ capability=$duty.capability; lease_id=$duty.lease_id; policy_epoch=$duty.policy_epoch; fence_token=$duty.fence_token; request_hash=$duty.request_hash })

            try {
                $controlBeforeEffect = Read-Arko95OpsJson -Path $paths.Control
                $chainBeforeEffect = Get-Arko95OpsReceiptChainStatus -Paths $paths
                if ([bool]$controlBeforeEffect.kill_latched -or [string]$controlBeforeEffect.desired_state -ne 'running') { throw 'kill_latch_changed_before_effect' }
                if (-not $chainBeforeEffect.Valid) { throw 'receipt_chain_invalid_before_effect' }
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Invoke-Arko95OpsCapability -ProjectRoot $ProjectRoot -Paths $paths -Policy $policy -CapabilityDefinition $capabilityDefinition -Duty $duty
                $stopwatch.Stop()
                $review = Invoke-Arko95OpsPostReview -Paths $paths -Duty $duty -CapabilityDefinition $capabilityDefinition -Result $result -DurationSeconds $stopwatch.Elapsed.TotalSeconds -Preflight $preflight
                $reviewPath = Join-Path $paths.Reviews (([string]$duty.duty_id) + '.json')
                Write-Arko95OpsJsonAtomic -Path $reviewPath -Value ([ordered]@{ schema_version=1; duty_id=$duty.duty_id; capability=$duty.capability; duration_seconds=[math]::Round($stopwatch.Elapsed.TotalSeconds,3); decision=$review.decision; parent_final_judgment_required=$true; reviews=$review.reviews; created_at=[DateTimeOffset]::UtcNow.ToString('o') })
                $reviewHash = (Get-FileHash -LiteralPath $reviewPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if (-not $review.passed) {
                    $duty.status = 'held'; $duty.hold_reason = 'post_review_rejected'; $duty.result = $result; $duty.review_path = $reviewPath; $duty.review_hash = $reviewHash
                    Write-Arko95OpsJsonAtomic -Path $workingPath -Value $duty
                    $null = Move-Arko95OpsDuty -Source $workingPath -DestinationDirectory $paths.Held
                    Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'post_review_rejected' -DutyId ([string]$duty.duty_id) -FaultClass 'adverse_review'
                    break
                }
                $duty.status = 'verified'
                $duty.completed_at = [DateTimeOffset]::UtcNow.ToString('o')
                $duty.duration_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds,3)
                $duty.result = $result
                $duty.review_path = $reviewPath
                $duty.review_hash = $reviewHash
                $duty.parent_final_judgment_required = $true
                Write-Arko95OpsJsonAtomic -Path $workingPath -Value $duty
                $completedPath = Move-Arko95OpsDuty -Source $workingPath -DestinationDirectory $paths.Completed
                try {
                    $receipt = Add-Arko95OpsEvent -Paths $paths -EventType 'duty_verified' -DutyId ([string]$duty.duty_id) -Payload ([ordered]@{ capability=$duty.capability; request_hash=$duty.request_hash; fence_token=$duty.fence_token; artifact_hashes=$result.ArtifactHashes; review_hash=$reviewHash; duration_seconds=$duty.duration_seconds; parent_final_judgment_required=$true })
                    $processed.Add([pscustomobject]@{ duty_id=$duty.duty_id; capability=$duty.capability; status='verified'; receipt_hash=$receipt.event_hash; completed_path=$completedPath })
                }
                catch {
                    $heldPath = Move-Arko95OpsDuty -Source $completedPath -DestinationDirectory $paths.Held
                    $heldDuty = Read-Arko95OpsJson -Path $heldPath
                    $heldDuty.status = 'held'; $heldDuty.hold_reason = 'completion_receipt_failed'
                    Write-Arko95OpsJsonAtomic -Path $heldPath -Value $heldDuty
                    Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'completion_receipt_failed' -DutyId ([string]$duty.duty_id) -FaultClass 'audit_failure'
                    break
                }
                $runtime = Read-Arko95OpsJson -Path $paths.Runtime
                $runtime.duties_completed = [int]$runtime.duties_completed + 1
                $runtime.consecutive_failures = 0
                $runtime.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
                Write-Arko95OpsJsonAtomic -Path $paths.Runtime -Value $runtime
                $lease = Read-Arko95OpsJson -Path $paths.Lease
                $today = [DateTimeOffset]::UtcNow.UtcDateTime.ToString('yyyy-MM-dd')
                if ([string]$lease.invocation_window_date -ne $today) { $lease.invocation_window_date = $today; $lease.invocations_today = 0 }
                $lease.invocations_today = [int]$lease.invocations_today + 1
                if ([int]$lease.invocations_today -gt [int]$lease.max_invocations_per_day) {
                    Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'daily_invocation_budget_exceeded' -FaultClass 'resource_budget'
                    break
                }
                Write-Arko95OpsJsonAtomic -Path $paths.Lease -Value $lease
            }
            catch {
                if (Test-Path -LiteralPath $workingPath -PathType Leaf) {
                    $failedDuty = Read-Arko95OpsJson -Path $workingPath
                    $failedDuty.status = 'failed'
                    $failedDuty.failure_reason = (($_.Exception.Message -replace '[\u0000-\u001F\u007F]+',' ') -replace '\s+',' ').Trim()
                    $failedDuty.failed_at = [DateTimeOffset]::UtcNow.ToString('o')
                    Write-Arko95OpsJsonAtomic -Path $workingPath -Value $failedDuty
                    $null = Move-Arko95OpsDuty -Source $workingPath -DestinationDirectory $paths.Failed
                }
                try { $null = Add-Arko95OpsEvent -Paths $paths -EventType 'duty_failed' -DutyId ([string]$duty.duty_id) -Payload ([ordered]@{ capability=$duty.capability; reason=$_.Exception.Message }) } catch { }
                Invoke-Arko95OpsTripCircuit -Paths $paths -Reason ('duty_failed:' + $_.Exception.Message) -DutyId ([string]$duty.duty_id) -FaultClass 'handler_failure'
                break
            }
        }

        $runtime = Read-Arko95OpsJson -Path $paths.Runtime
        if ([string]$runtime.circuit_state -eq 'closed') {
            $runtime.cycles_completed = [int]$runtime.cycles_completed + 1
            $runtime.last_cycle_at = [DateTimeOffset]::UtcNow.ToString('o')
            $runtime.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
            Write-Arko95OpsJsonAtomic -Path $paths.Runtime -Value $runtime
            $lease = Read-Arko95OpsJson -Path $paths.Lease
            $lease.expires_at = [DateTimeOffset]::UtcNow.AddHours([double]$policy.lease.duration_hours).ToString('o')
            Write-Arko95OpsJsonAtomic -Path $paths.Lease -Value $lease
            Set-Arko95OpsHeartbeat -Paths $paths -WorkerInstance $workerInstance -CycleId $cycleId -Status 'idle' -Details ([ordered]@{ processed=$processed.Count; scheduled=$scheduled })
        }
        else {
            Set-Arko95OpsHeartbeat -Paths $paths -WorkerInstance $workerInstance -CycleId $cycleId -Status 'circuit_open' -Details ([ordered]@{ processed=$processed.Count })
        }
        return [pscustomobject]@{ CycleId=$cycleId; Status=$(if ([string]$runtime.circuit_state -eq 'closed') {'completed'} else {'circuit_open'}); Scheduled=$scheduled; Processed=$processed.ToArray(); Operations=Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot }
    }
    catch {
        if ($null -ne $paths -and (Test-Path -LiteralPath $paths.Control -PathType Leaf)) {
            try { Invoke-Arko95OpsTripCircuit -Paths $paths -Reason ('cycle_exception:' + $_.Exception.Message) -FaultClass 'cycle_exception' } catch { }
            try { Set-Arko95OpsHeartbeat -Paths $paths -WorkerInstance $workerInstance -CycleId $cycleId -Status 'faulted' -Details ([ordered]@{ reason=$_.Exception.Message }) } catch { }
        }
        throw
    }
    finally { Exit-Arko95OperationsMutex -Mutex $mutex }
}

Export-ModuleMember -Function Get-Arko95OperationsPaths, Get-Arko95OperationsPolicy, Initialize-Arko95Operations, Enable-Arko95Operations, Stop-Arko95Operations, Get-Arko95OperationsStatus, Test-Arko95OperationsReceiptChain, New-Arko95OperationsDuty, Invoke-Arko95OperationsCycle

