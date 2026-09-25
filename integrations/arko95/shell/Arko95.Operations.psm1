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
    })
    if ($null -ne $lease) {
        $lease.status = 'faulted'
        $lease.revoked_at = $now
        $lease.revocation_reason = $Reason
        Write-Arko95OpsJsonAtomic -Path $Paths.Lease -Value $lease
    }
    Write-Arko95OpsJsonAtomic -Path $Paths.Runtime -Value ([ordered]@{
        schema_version       = 1
        circuit_state        = 'open'
        consecutive_failures = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'consecutive_failures' -Default 0) + 1
        cycles_completed     = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'cycles_completed' -Default 0)
        duties_completed     = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_completed' -Default 0)
        duties_failed        = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_failed' -Default 0) + $(if ([string]::IsNullOrWhiteSpace($DutyId)) { 0 } else { 1 })
        last_fault           = $Reason
        last_fault_class     = $FaultClass
        last_cycle_at        = Get-Arko95OpsProperty -InputObject $runtime -Name 'last_cycle_at'
        updated_at           = $now
    })
    try { $null = Add-Arko95OpsEvent -Paths $Paths -EventType 'circuit_opened' -DutyId $DutyId -Payload ([ordered]@{ reason = $Reason; fault_class = $FaultClass }) } catch { }
}

function Enable-Arko95Operations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Acknowledgement,
        [string]$StateRoot
    )
    $required = 'I authorize bounded R0/R1 ARKO-95 operations'
    if ($Acknowledgement -cne $required) { throw "Enabling Operations VP requires the exact acknowledgement: $required" }
    $mutex = $null
    try {
        $mutex = Enter-Arko95OperationsMutex -ProjectRoot $ProjectRoot
        $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        Initialize-Arko95OperationsState -ProjectRoot $ProjectRoot -Paths $paths
        $policy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
        $chain = Get-Arko95OpsReceiptChainStatus -Paths $paths
        if (-not $chain.Valid) { throw "Cannot enable against an invalid receipt chain: $($chain.Error)" }
        $control = Read-Arko95OpsJson -Path $paths.Control
        $epoch = [int](Get-Arko95OpsProperty -InputObject $control -Name 'policy_epoch' -Default 0) + 1
        $now = [DateTimeOffset]::UtcNow
        $allowedCapabilities = @($policy.automatic_capabilities | ForEach-Object { [string]$_.id })
        $lease = [ordered]@{
            schema_version          = 1
            lease_id                = 'lease-' + [guid]::NewGuid().ToString('D')
            status                  = 'active'
            policy_epoch            = $epoch
            issued_at               = $now.ToString('o')
            expires_at              = $now.AddHours([double]$policy.lease.duration_hours).ToString('o')
            renewal_mode            = 'sliding_while_healthy'
            issued_by               = 'local_owner_explicit_request'
            allowed_capabilities    = $allowedCapabilities
            allowed_risk_tiers      = @($policy.lease.automatic_risk_tiers)
            invocation_window_date  = $now.UtcDateTime.ToString('yyyy-MM-dd')
            invocations_today       = 0
            max_invocations_per_day = [int]$policy.lease.max_invocations_per_day
            execution_authority     = 'only_enumerated_r0_r1_handlers'
            revoked_at              = $null
            revocation_reason       = ''
        }
        Write-Arko95OpsJsonAtomic -Path $paths.Control -Value ([ordered]@{
            schema_version = 1; desired_state = 'running'; kill_latched = $false; reason = 'owner_enabled_bounded_operations'; policy_epoch = $epoch; updated_at = $now.ToString('o'); updated_by = 'local_owner'
        })
        Write-Arko95OpsJsonAtomic -Path $paths.Lease -Value $lease
        $runtime = Read-Arko95OpsJson -Path $paths.Runtime
        Write-Arko95OpsJsonAtomic -Path $paths.Runtime -Value ([ordered]@{
            schema_version = 1; circuit_state = 'closed'; consecutive_failures = 0; cycles_completed = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'cycles_completed' -Default 0); duties_completed = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_completed' -Default 0); duties_failed = [int](Get-Arko95OpsProperty -InputObject $runtime -Name 'duties_failed' -Default 0); last_fault = ''; last_fault_class = ''; last_cycle_at = Get-Arko95OpsProperty -InputObject $runtime -Name 'last_cycle_at'; updated_at = $now.ToString('o')
        })
        try {
            $null = Add-Arko95OpsEvent -Paths $paths -EventType 'operations_enabled' -Payload ([ordered]@{ lease_id = $lease.lease_id; policy_epoch = $epoch; capabilities = $allowedCapabilities; boundary = 'R0_R1_only' })
        }
        catch {
            Invoke-Arko95OpsTripCircuit -Paths $paths -Reason 'enable_receipt_failed' -FaultClass 'audit_failure'
            throw
        }
        return Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    }
    finally { Exit-Arko95OperationsMutex -Mutex $mutex }
}

function Stop-Arko95Operations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$Reason = 'owner_stop',
        [string]$StateRoot
    )
    $mutex = $null
    try {
        $mutex = Enter-Arko95OperationsMutex -ProjectRoot $ProjectRoot
        $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        Initialize-Arko95OperationsState -ProjectRoot $ProjectRoot -Paths $paths
        Invoke-Arko95OpsTripCircuit -Paths $paths -Reason $Reason -FaultClass 'owner_stop'
        return Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    }
    finally { Exit-Arko95OperationsMutex -Mutex $mutex }
}

function Get-Arko95OpsResourceSnapshot {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $cpu = $null
    $freeMemory = $null
    $totalMemory = $null
    $diskFree = $null
    $probeError = $null
    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        if ($processors.Count -gt 0) { $cpu = [math]::Round(($processors | Measure-Object -Property LoadPercentage -Average).Average, 1) }
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $freeMemory = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
        $totalMemory = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
        $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($ProjectRoot))
        $drive = [System.IO.DriveInfo]::new($root)
        if ($drive.IsReady) { $diskFree = [math]::Round($drive.AvailableFreeSpace / 1GB, 2) }
    }
    catch { $probeError = $_.Exception.Message }
    [pscustomobject]@{
        timestamp_utc = [DateTimeOffset]::UtcNow.ToString('o')
        cpu_percent = $cpu
        free_memory_gb = $freeMemory
        total_memory_gb = $totalMemory
        disk_free_gb = $diskFree
        network_available = [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
        probe_error = $probeError
    }
}

function Test-Arko95OpsResourceAdmission {
    param(
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$Snapshot
    )
    $reasons = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.probe_error)) { $reasons.Add('resource_probe_failed') }
    if ($null -eq $Snapshot.cpu_percent -or [double]$Snapshot.cpu_percent -gt [double]$Policy.resource_guard.maximum_cpu_percent) { $reasons.Add('cpu_pressure_or_unknown') }
    if ($null -eq $Snapshot.free_memory_gb -or [double]$Snapshot.free_memory_gb -lt [double]$Policy.resource_guard.minimum_free_memory_gb) { $reasons.Add('memory_pressure_or_unknown') }
    if ($null -eq $Snapshot.disk_free_gb -or [double]$Snapshot.disk_free_gb -lt [double]$Policy.resource_guard.minimum_free_disk_gb) { $reasons.Add('disk_pressure_or_unknown') }
    [pscustomobject]@{ Admitted = $reasons.Count -eq 0; Reasons = $reasons.ToArray(); Snapshot = $Snapshot }
}

function ConvertTo-Arko95OpsParameters {
    param([AllowNull()]$Parameters)
    $normalized = [ordered]@{}
    if ($null -eq $Parameters) { return $normalized }
    if ($Parameters -is [System.Collections.IDictionary]) {
        foreach ($key in @($Parameters.Keys | Sort-Object)) { $normalized[[string]$key] = $Parameters[$key] }
    }
    else {
        foreach ($property in @($Parameters.PSObject.Properties | Sort-Object Name)) { $normalized[$property.Name] = $property.Value }
    }
    return $normalized
}

function Find-Arko95OpsDutyPath {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$FileName
    )
    foreach ($directory in @($Paths.Pending,$Paths.Working,$Paths.Completed,$Paths.Failed,$Paths.Held)) {
        $candidate = Join-Path $directory $FileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Add-Arko95OpsDutyUnlocked {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][string]$Capability,
        [AllowNull()]$Parameters,
        [Parameter(Mandatory)][string]$IdempotencyKey,
        [int]$Priority = 2,
        [string]$RequestedBy = 'local_owner'
    )
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey) -or $IdempotencyKey.Length -gt 180 -or $IdempotencyKey -match '[\u0000-\u001F\u007F]') { throw 'Duty idempotency key is missing or invalid.' }
    if ($Priority -lt 0 -or $Priority -gt 4) { throw 'Duty priority must be between zero and four.' }
    $capabilityDefinition = Get-Arko95OpsCapability -Policy $Policy -CapabilityId $Capability
    if ($null -eq $capabilityDefinition) { throw "Capability '$Capability' is not in the automatic broker allowlist." }
    $normalizedParameters = ConvertTo-Arko95OpsParameters -Parameters $Parameters
    $allowedFields = @($capabilityDefinition.allowed_parameter_fields | ForEach-Object { [string]$_ })
    foreach ($parameterName in @($normalizedParameters.Keys)) {
        if ($parameterName -notin $allowedFields) { throw "Capability '$Capability' does not accept parameter '$parameterName'." }
    }
    $requestMaterial = [ordered]@{ capability = $Capability; parameters = $normalizedParameters }
    $requestHash = Get-Arko95OpsObjectHash -Value $requestMaterial
    $keyHash = Get-Arko95OpsStringHash -Text $IdempotencyKey
    $fileName = 'duty-' + $keyHash.Substring(0, 32) + '.json'
    $existingPath = Find-Arko95OpsDutyPath -Paths $Paths -FileName $fileName
    if (-not [string]::IsNullOrWhiteSpace($existingPath)) {
        $existing = Read-Arko95OpsJson -Path $existingPath
        if ([string]$existing.request_hash -cne $requestHash) { throw 'The idempotency key was reused for a different duty request.' }
        return [pscustomobject]@{ Created = $false; Duty = $existing; Path = $existingPath }
    }
    if ((Get-Arko95OpsQueueCounts -Paths $Paths).pending -ge [int]$Policy.scheduler.max_queue_depth) { throw 'Operations duty queue is full.' }
    $cleanRequestedBy = (($RequestedBy -replace '[\u0000-\u001F\u007F]+',' ') -replace '\s+',' ').Trim()
    if ($cleanRequestedBy.Length -gt 80) { $cleanRequestedBy = $cleanRequestedBy.Substring(0,80) }
    $duty = [ordered]@{
        schema_version    = 1
        duty_id           = 'duty-' + [guid]::NewGuid().ToString('D')
        capability        = $Capability
        parameters        = $normalizedParameters
        idempotency_key   = $IdempotencyKey
        request_hash      = $requestHash
        requested_by      = $cleanRequestedBy
        priority          = $Priority
        status            = 'pending'
        attempts          = 0
        fence_token       = 0
        created_at        = [DateTimeOffset]::UtcNow.ToString('o')
        not_before        = $null
        claimed_at        = $null
        completed_at      = $null
        failed_at         = $null
        hold_reason       = ''
        failure_reason    = ''
        worker_instance   = ''
        lease_id          = ''
        policy_epoch      = 0
        preflight         = $null
        result            = $null
        review_path       = $null
        review_hash       = $null
        duration_seconds  = $null
        parent_final_judgment_required = $true
        execution_authority = $false
    }
    $targetPath = Join-Path $Paths.Pending $fileName
    Write-Arko95OpsJsonAtomic -Path $targetPath -Value $duty
    try { $null = Add-Arko95OpsEvent -Paths $Paths -EventType 'duty_enqueued' -DutyId $duty.duty_id -Payload ([ordered]@{ capability = $Capability; request_hash = $requestHash; idempotency_key_hash = $keyHash; requested_by = $cleanRequestedBy }) }
    catch {
        $duty.status = 'held'
        $duty.hold_reason = 'enqueue_receipt_failed'
        Write-Arko95OpsJsonAtomic -Path $targetPath -Value $duty
        [System.IO.File]::Move($targetPath, (Join-Path $Paths.Held $fileName), $true)
        throw
    }
    return [pscustomobject]@{ Created = $true; Duty = [pscustomobject]$duty; Path = $targetPath }
}

function New-Arko95OperationsDuty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)][string]$IdempotencyKey,
        [AllowNull()]$Parameters = $null,
        [int]$Priority = 2,
        [string]$RequestedBy = 'local_owner',
        [string]$StateRoot
    )
    $mutex = $null
    try {
        $mutex = Enter-Arko95OperationsMutex -ProjectRoot $ProjectRoot
        $paths = Get-Arko95OperationsPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        Initialize-Arko95OperationsState -ProjectRoot $ProjectRoot -Paths $paths
        $policy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
        return Add-Arko95OpsDutyUnlocked -Paths $paths -Policy $policy -Capability $Capability -Parameters $Parameters -IdempotencyKey $IdempotencyKey -Priority $Priority -RequestedBy $RequestedBy
    }
    finally { Exit-Arko95OperationsMutex -Mutex $mutex }
}

function Add-Arko95OpsRecurringDuties {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Policy
    )
    $nowSeconds = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $created = 0
    foreach ($schedule in @($Policy.recurring_duties)) {
        $everySeconds = [int]$schedule.every_seconds
        $bucket = [math]::Floor($nowSeconds / $everySeconds)
        $key = 'schedule:{0}:{1}' -f [string]$schedule.id, [int64]$bucket
        $result = Add-Arko95OpsDutyUnlocked -Paths $Paths -Policy $Policy -Capability ([string]$schedule.capability) -Parameters ([ordered]@{}) -IdempotencyKey $key -Priority ([int]$schedule.priority) -RequestedBy 'operations_scheduler'
        if ($result.Created) { $created++ }
    }
    return $created
}

function Write-Arko95OpsReportResult {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Duty,
        [Parameter(Mandatory)][string]$ReportKind,
        [Parameter(Mandatory)]$Report,
        [string]$Summary = 'completed'
    )
    $safeKind = $ReportKind -replace '[^a-z0-9_-]','-'
    $reportPath = Join-Path $Paths.Reports ('{0}-{1}.json' -f $safeKind, [string]$Duty.duty_id)
    Write-Arko95OpsJsonAtomic -Path $reportPath -Value $Report
    $hash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        Success        = $true
        Summary        = $Summary
        ArtifactPaths  = @($reportPath)
        ArtifactHashes = [ordered]@{ $reportPath = $hash }
        Reversible     = $true
        Rollback       = 'Archive this generated report inside operations state after owner review.'
    }
}

function Invoke-Arko95OpsCapability {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$CapabilityDefinition,
        [Parameter(Mandatory)]$Duty
    )
    $handler = [string]$CapabilityDefinition.handler
    switch ($handler) {
        'system_health_snapshot' {
            $snapshot = Get-Arko95OpsResourceSnapshot -ProjectRoot $ProjectRoot
            $admission = Test-Arko95OpsResourceAdmission -Policy $Policy -Snapshot $snapshot
            $report = [ordered]@{
                schema_version = 1
                report_kind = 'system_health_snapshot'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                duty_id = [string]$Duty.duty_id
                snapshot = $snapshot
                admission = [ordered]@{ admitted = $admission.Admitted; reasons = @($admission.Reasons) }
                scope = 'coarse_nonsecret_local_health'
            }
            return Write-Arko95OpsReportResult -Paths $Paths -Duty $Duty -ReportKind 'health' -Report $report -Summary 'Coarse local system health captured.'
        }
        'receipt_chain_audit' {
            $chain = Get-Arko95OpsReceiptChainStatus -Paths $Paths
            $report = [ordered]@{
                schema_version = 1
                report_kind = 'receipt_chain_audit'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                duty_id = [string]$Duty.duty_id
                valid = $chain.Valid
                event_count = $chain.EventCount
                head_hash = $chain.HeadHash
                error = $chain.Error
                limitation = 'Hash chaining detects accidental or ordinary modification but is not an external immutable anchor.'
            }
            if (-not $chain.Valid) { throw "Receipt chain audit failed: $($chain.Error)" }
            return Write-Arko95OpsReportResult -Paths $Paths -Duty $Duty -ReportKind 'receipt-audit' -Report $report -Summary 'Operations receipt chain verified.'
        }
        'delegation_receipt_verify' {
            $available = Test-Path -LiteralPath $Paths.DelegationPlan -PathType Leaf
            $valid = if ($available) { Test-Arko95DelegationReceipt -PlanPath $Paths.DelegationPlan } else { $false }
            $report = [ordered]@{
                schema_version = 1
                report_kind = 'delegation_receipt_verify'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                duty_id = [string]$Duty.duty_id
                available = $available
                valid = $valid
                plan_path = if ($available) { $Paths.DelegationPlan } else { $null }
                interpretation = if (-not $available) { 'No delegation receipt has been staged.' } elseif ($valid) { 'Delegation receipt is internally consistent.' } else { 'Delegation receipt failed verification.' }
            }
            if ($available -and -not $valid) { throw 'The latest delegation receipt failed verification.' }
            return Write-Arko95OpsReportResult -Paths $Paths -Duty $Duty -ReportKind 'delegation-audit' -Report $report -Summary $(if ($available) { 'Delegation receipt verified.' } else { 'No delegation receipt was available; no authority inferred.' })
        }
        'operations_brief' {
            $queue = Get-Arko95OpsQueueCounts -Paths $Paths
            $control = Read-Arko95OpsJson -Path $Paths.Control
            $runtime = Read-Arko95OpsJson -Path $Paths.Runtime
            $lease = Read-Arko95OpsJson -Path $Paths.Lease
            $chain = Get-Arko95OpsReceiptChainStatus -Paths $Paths
            $report = [ordered]@{
                schema_version = 1
                report_kind = 'operations_brief'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                duty_id = [string]$Duty.duty_id
                control = [ordered]@{ desired_state = $control.desired_state; kill_latched = $control.kill_latched; reason = $control.reason; policy_epoch = $control.policy_epoch }
                circuit = [ordered]@{ state = $runtime.circuit_state; last_fault = $runtime.last_fault; failures = $runtime.consecutive_failures }
                lease = [ordered]@{ status = $lease.status; lease_id = $lease.lease_id; expires_at = $lease.expires_at; invocations_today = $lease.invocations_today }
                queue = $queue
                receipt_chain = [ordered]@{ valid = $chain.Valid; event_count = $chain.EventCount; head_hash = $chain.HeadHash }
                authority = 'Only enumerated R0/R1 handlers; all consequential actions remain gated.'
            }
            $result = Write-Arko95OpsReportResult -Paths $Paths -Duty $Duty -ReportKind 'brief' -Report $report -Summary 'Operations brief generated.'
            Write-Arko95OpsJsonAtomic -Path $Paths.LatestBrief -Value $report
            $latestHash = (Get-FileHash -LiteralPath $Paths.LatestBrief -Algorithm SHA256).Hash.ToLowerInvariant()
            $result.ArtifactPaths = @($result.ArtifactPaths) + @($Paths.LatestBrief)
            $result.ArtifactHashes[$Paths.LatestBrief] = $latestHash
            return $result
        }
        'operations_workspace_maintain' {
            $directories = @($Paths.Pending,$Paths.Working,$Paths.Completed,$Paths.Failed,$Paths.Held,$Paths.Reports,$Paths.Reviews)
            $checks = foreach ($directory in $directories) {
                $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
                [ordered]@{ path = $directory; exists = $true; reparse_point = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) }
            }
            if (@($checks | Where-Object { $_.reparse_point }).Count -gt 0) { throw 'An operations workspace directory became a reparse point.' }
            $report = [ordered]@{
                schema_version = 1
                report_kind = 'operations_workspace_maintain'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                duty_id = [string]$Duty.duty_id
                directories = $checks
                queue = Get-Arko95OpsQueueCounts -Paths $Paths
                effect = 'verify_and_create_only; no user data deleted or moved'
            }
            return Write-Arko95OpsReportResult -Paths $Paths -Duty $Duty -ReportKind 'workspace' -Report $report -Summary 'Operations workspace boundaries verified.'
        }
        default { throw "Handler '$handler' is not compiled into Operations VP." }
    }
}

function Invoke-Arko95OpsPreflightReview {
    param(
        [Parameter(Mandatory)]$Duty,
        [Parameter(Mandatory)]$CapabilityDefinition,
        [Parameter(Mandatory)]$Control,
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)]$Policy
    )
    $reasons = [Collections.Generic.List[string]]::new()
    if ([bool]$Control.kill_latched -or [string]$Control.desired_state -ne 'running') { $reasons.Add('kill_latch_or_control_not_running') }
    if ([string]$Lease.status -ne 'active') { $reasons.Add('lease_not_active') }
    if ([int]$Lease.policy_epoch -ne [int]$Control.policy_epoch) { $reasons.Add('lease_epoch_mismatch') }
    if ([string]$Duty.capability -notin @($Lease.allowed_capabilities | ForEach-Object { [string]$_ })) { $reasons.Add('capability_not_in_lease') }
    if ([string]$CapabilityDefinition.risk_tier -notin @($Policy.lease.automatic_risk_tiers | ForEach-Object { [string]$_ })) { $reasons.Add('risk_tier_not_automatic') }
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
