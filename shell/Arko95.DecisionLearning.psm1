Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'Arko95.Operations.psm1')
Import-Module (Join-Path $PSScriptRoot 'Arko95.MissionControl.psm1')

function Get-Arko95LearningHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-Arko95LearningObjectHash {
    param([Parameter(Mandatory)]$Value)
    return Get-Arko95LearningHash -Text ($Value | ConvertTo-Json -Compress -Depth 40)
}

function ConvertTo-Arko95LearningText {
    param(
        [AllowNull()]$Value,
        [int]$MaximumLength = 1000,
        [string]$Fallback = ''
    )
    if ($null -eq $Value) { return $Fallback }
    $clean = (([string]$Value -replace '[\u0000-\u001F\u007F]+',' ') -replace '\s+',' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }
    if ($clean.Length -gt $MaximumLength) { return $clean.Substring(0,$MaximumLength) }
    return $clean
}

function Test-Arko95LearningCredentialText {
    param([Parameter(Mandatory)][string]$Text)
    $namedSecret = '(?i)(password|passwd|api[ _-]?key|access[ _-]?token|refresh[ _-]?token|client[ _-]?secret|private[ _-]?key|recovery[ _-]?code)\s*[:=]\s*\S+'
    $longToken = '(?<![A-Za-z0-9])[A-Za-z0-9_\-\/+]{48,}={0,2}(?![A-Za-z0-9])'
    return ($Text -match $namedSecret) -or ($Text -match $longToken)
}

function Get-Arko95DecisionLearningPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $core = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = Join-Path $core.StateDir 'decision-learning' }
    $candidate = [System.IO.Path]::GetFullPath($StateRoot)
    $stateRoot = [System.IO.Path]::GetFullPath($core.StateDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if (-not $candidate.StartsWith($stateRoot + [System.IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Decision Learning state must remain beneath this project state directory.'
    }
    [pscustomobject]@{
        Root = $candidate
        Policy = Join-Path $core.Root 'config\decision-learning.json'
        Ledger = Join-Path $candidate 'ledger.jsonl'
        Projection = Join-Path $candidate 'projection.json'
        Adapters = Join-Path $candidate 'adapter-observations'
    }
}

function Get-Arko95DecisionLearningPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $paths = Get-Arko95DecisionLearningPaths -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $paths.Policy -PathType Leaf)) { throw 'Decision Learning policy is missing.' }
    $policy = Get-Content -Raw -LiteralPath $paths.Policy | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String
    if ($policy.schema_version -ne 1 -or $policy.mode -ne 'shadow_learning' -or $policy.default_effect -ne 'proposal_only') {
        throw 'Decision Learning must remain schema v1, shadow-only, and proposal-only.'
    }
    if ($policy.maximum_open_cycles -ne 1 -or $policy.mission_binding_required -ne $true) {
        throw 'Decision Learning must remain bound to one mission and one open cycle.'
    }
    if ($policy.credit_budget.exploration_cap_percent -ne 25 -or $policy.credit_budget.protected_execution_evidence_percent -ne 75 -or $policy.credit_budget.hard_fail_on_overage -ne $true) {
        throw 'The 25/75 credit boundary changed.'
    }
    $expectedKinds = @('observation','inference','projection','decision_proposal','outcome','lesson_candidate')
    $actualKinds = @($policy.record_kinds | ForEach-Object { [string]$_.id })
    if (($actualKinds -join '|') -cne ($expectedKinds -join '|')) { throw 'The typed compounding pipeline changed or is incomplete.' }
    $expectedAdapters = @('openclaw_companion','microsoft_copilot','chatgpt','codex')
    $actualAdapters = @($policy.adapters | ForEach-Object { [string]$_.id })
    if (($actualAdapters -join '|') -cne ($expectedAdapters -join '|')) { throw 'The four-slot AI adapter fabric changed or is incomplete.' }
    foreach ($adapter in @($policy.adapters)) {
        if (@($adapter.allowed_claims).Count -lt 1) { throw "Adapter $($adapter.id) is missing its closed claim allowlist." }
        if ($adapter.effect -ne 'proposal_only' -or $adapter.may_write_mission_events -ne $false -or $adapter.may_invoke_operations -ne $false -or $adapter.may_approve -ne $false -or $adapter.may_promote_learning -ne $false -or $adapter.may_clear_kill_latch -ne $false) {
            throw "Adapter $($adapter.id) gained control, execution, approval, learning-promotion, or kill authority."
        }
    }
    if ($policy.learning_promotion_default -ne 'proposed_only' -or $policy.execution_authority -ne 'operations_vp_only') {
        throw 'Learning promotion or execution authority escaped its boundary.'
    }
    return $policy
}

function Enter-Arko95LearningMutex {
    param([Parameter(Mandatory)][string]$StateRoot)
    $digest = Get-Arko95LearningHash -Text ([System.IO.Path]::GetFullPath($StateRoot).ToLowerInvariant())
    $mutex = [Threading.Mutex]::new($false,('Local\ARKO95-DecisionLearning-' + $digest.Substring(0,20)))
    try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10)) }
    catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { $mutex.Dispose(); throw 'Decision Learning is busy in another process.' }
    return $mutex
}

function Exit-Arko95LearningMutex {
    param([AllowNull()]$Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

function Initialize-Arko95LearningState {
    param([Parameter(Mandatory)]$Paths)
    foreach ($directory in @($Paths.Root,$Paths.Adapters)) {
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $item = Get-Item -LiteralPath $directory -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Decision Learning refuses reparse-point state directories.' }
    }
    if (-not (Test-Path -LiteralPath $Paths.Ledger -PathType Leaf)) {
        [System.IO.File]::WriteAllText($Paths.Ledger,'',[System.Text.UTF8Encoding]::new($false))
    }
}

function Read-Arko95LearningEvents {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt 8388608) { throw 'Decision Learning ledger exceeds its v1 size limit.' }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Decision Learning refuses a ledger reparse point.' }
    $events = [Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 131072) { throw 'Decision Learning event exceeds its v1 size limit.' }
        $events.Add(($line | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String))
    }
    return $events.ToArray()
}

function Get-Arko95LearningEventHashMaterial {
    param([Parameter(Mandatory)]$Event)
    [ordered]@{
        schema_version = [int]$Event.schema_version
        sequence = [int]$Event.sequence
        event_id = [string]$Event.event_id
        cycle_id = [string]$Event.cycle_id
        mission_id = [string]$Event.mission_id
        objective_sha256 = [string]$Event.objective_sha256
        timestamp = [string]$Event.timestamp
        event_type = [string]$Event.event_type
        actor_id = [string]$Event.actor_id
        actor_role = [string]$Event.actor_role
        expected_version = [int]$Event.expected_version
        new_version = [int]$Event.new_version
        policy_sha256 = [string]$Event.policy_sha256
        payload = $Event.payload
        previous_hash = [string]$Event.previous_hash
    }
}

function Get-Arko95LearningRecordHashMaterial {
    param([Parameter(Mandatory)]$Record)
    [ordered]@{
        schema_version = [int]$Record.schema_version
        record_id = [string]$Record.record_id
        cycle_id = [string]$Record.cycle_id
        mission_id = [string]$Record.mission_id
        objective_sha256 = [string]$Record.objective_sha256
        kind = [string]$Record.kind
        lane = [string]$Record.lane
        credit_class = [string]$Record.credit_class
        credit_cost = [int]$Record.credit_cost
        producer_id = [string]$Record.producer_id
        adapter_id = [string]$Record.adapter_id
        source_reference = [string]$Record.source_reference
        created_at = [string]$Record.created_at
        content = [string]$Record.content
        content_sha256 = [string]$Record.content_sha256
        confidence = [int]$Record.confidence
        uncertainty = [string]$Record.uncertainty
        parent_record_ids = @($Record.parent_record_ids)
        parent_record_sha256 = @($Record.parent_record_sha256)
        evidence_sha256 = @($Record.evidence_sha256)
        suggested_operations_capability = [string]$Record.suggested_operations_capability
        control_effect = [string]$Record.control_effect
        promotion_state = [string]$Record.promotion_state
    }
}

function Get-Arko95AdapterReceiptHashMaterial {
    param([Parameter(Mandatory)]$Receipt)
    [ordered]@{
        schema_version = [int]$Receipt.schema_version
        receipt_kind = [string]$Receipt.receipt_kind
        adapter_id = [string]$Receipt.adapter_id
        adapter_version = [string]$Receipt.adapter_version
        host_or_tenant = [string]$Receipt.host_or_tenant
        source_reference = [string]$Receipt.source_reference
        observed_at = [string]$Receipt.observed_at
        fresh_until = [string]$Receipt.fresh_until
        source_kind = [string]$Receipt.source_kind
        connection_state = [string]$Receipt.connection_state
        claims = @($Receipt.claims)
        content_read = [bool]$Receipt.content_read
        credentials_read = [bool]$Receipt.credentials_read
        observation_sha256 = [string]$Receipt.observation_sha256
        mission_authority = [bool]$Receipt.mission_authority
        operations_authority = [bool]$Receipt.operations_authority
        approval_authority = [bool]$Receipt.approval_authority
        learning_promotion_authority = [bool]$Receipt.learning_promotion_authority
        sensitive_values_retained = [bool]$Receipt.sensitive_values_retained
    }
}

function Get-Arko95LearningKindPolicy {
    param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$Kind)
    $entry = @($Policy.record_kinds | Where-Object { [string]$_.id -eq $Kind })
    if ($entry.Count -ne 1) { throw "Unknown Decision Learning record kind '$Kind'." }
    return $entry[0]
}

function Test-Arko95LearningRecordAgainstCycle {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)]$Cycle,
        [Parameter(Mandatory)]$Policy
    )
    if ([string]$Record.cycle_id -cne [string]$Cycle.cycle_id -or [string]$Record.mission_id -cne [string]$Cycle.mission_id -or [string]$Record.objective_sha256 -cne [string]$Cycle.objective_sha256) {
        throw 'Record lineage crossed its cycle or mission boundary.'
    }
    if ([string]$Record.content_sha256 -cne (Get-Arko95LearningHash -Text ([string]$Record.content))) { throw 'Record content digest mismatch.' }
    $computedRecordHash = Get-Arko95LearningObjectHash -Value (Get-Arko95LearningRecordHashMaterial -Record $Record)
    if ([string]$Record.record_sha256 -cne $computedRecordHash) { throw 'Record digest mismatch.' }
    if ([int]$Record.credit_cost -lt 1 -or [int]$Record.credit_cost -gt 25) { throw 'Record credit cost is outside the bounded range.' }
    if ([int]$Record.confidence -lt 0 -or [int]$Record.confidence -gt 100) { throw 'Record confidence is outside 0-100.' }
    if ([string]$Record.control_effect -cne 'none') { throw 'A data record attempted to gain a control effect.' }

    $kindPolicy = Get-Arko95LearningKindPolicy -Policy $Policy -Kind ([string]$Record.kind)
    if ([string]$Record.lane -cne [string]$kindPolicy.lane -or [string]$Record.credit_class -cne [string]$kindPolicy.credit_class) {
        throw 'Record lane or credit class does not match policy.'
    }
    $parents = @($Record.parent_record_ids)
    $parentHashes = @($Record.parent_record_sha256)
    if ($parents.Count -ne $parentHashes.Count -or $parents.Count -lt [int]$kindPolicy.minimum_parents) { throw 'Record parent lineage is incomplete.' }
    if ($parents.Count -ne @($parents | Sort-Object -Unique).Count) { throw 'Record parent IDs contain duplicates.' }
    for ($i=0; $i -lt $parents.Count; $i++) {
        $parentId = [string]$parents[$i]
        if (-not $Cycle.record_index.ContainsKey($parentId)) { throw 'Record references an unknown or future parent.' }
        $parent = $Cycle.record_index[$parentId]
        if ([string]$parent.record_sha256 -cne [string]$parentHashes[$i]) { throw 'Record parent digest mismatch.' }
        if ([string]$parent.kind -notin @($kindPolicy.allowed_parent_kinds)) { throw "A $($Record.kind) record cannot derive from $($parent.kind)." }
    }
    if ([string]$Record.kind -eq 'observation' -and [string]::IsNullOrWhiteSpace([string]$Record.source_reference)) { throw 'An observation requires a source reference.' }
    if ([string]$Record.kind -eq 'outcome') {
        if ([string]::IsNullOrWhiteSpace([string]$Record.source_reference)) { throw 'An outcome requires a source or receipt reference.' }
        if (@($Record.evidence_sha256).Count -lt 1) { throw 'An outcome requires at least one receipt or evidence hash.' }
    }
    foreach ($hash in @($Record.evidence_sha256)) { if ([string]$hash -notmatch '^[a-f0-9]{64}$') { throw 'Record evidence hashes must be SHA-256.' } }
    if ([string]$Record.kind -ne 'decision_proposal' -and -not [string]::IsNullOrWhiteSpace([string]$Record.suggested_operations_capability)) {
        throw 'Only an inert decision proposal may name an Operations capability.'
    }
    if ([string]$Record.kind -eq 'decision_proposal' -and -not [string]::IsNullOrWhiteSpace([string]$Record.suggested_operations_capability)) {
        $opsPolicy = Get-Arko95OperationsPolicy -ProjectRoot $Cycle.project_root
        $allowed = @($opsPolicy.automatic_capabilities | ForEach-Object { [string]$_.id })
        if ([string]$Record.suggested_operations_capability -notin $allowed) { throw 'Decision proposal named a non-compiled Operations capability.' }
    }
    if ([string]$Record.kind -eq 'lesson_candidate' -and [string]$Record.promotion_state -cne 'proposed_only') {
        throw 'A lesson candidate attempted automatic promotio÷Ýú¶‰žËkºwµçAM½ÉÐµ=‰©•Ð€µU¹¥ÅÕ”¤(€€€¥˜€ ‘±•…¹±…¥µÌ¹½Õ¹Ð€µ±Ð€Ä¤ìÑ¡É½Ü€Ð±•…ÍÐ½¹”ÑåÁ•…‘…ÁÑ•È±…¥´¥ÌÉ•ÅÕ¥É•¸œô(€€€™½É•… € ‘±…¥´¥¸€‘±•…¹±…¥µÌ¤ì¥˜€ ‘±…¥´€µ¹½Ñ¥¸  ‘…‘…ÁÑ•ÉA½±¥ä¹…±±½Ý•‘}±…¥µÌ¤¤ìÑ¡É½Ü€‰‘…ÁÑ•È±…¥´€œ‘±…¥´œ¥Ì¹½Ð…±±½Ý•™½È€‘‘…ÁÑ•É%¸ˆôô(€€€€‘É••¥ÁÐ€ôm½É‘•É•‘uì(€€€€€€€Í¡•µ…}Ù•ÉÍ¥½¸€ô€Ä(€€€€€€€É••¥ÁÑ}­¥¹€ô€…‘…ÁÑ•É}½‰Í•ÉÙ…Ñ¥½¸œ(€€€€€€€…‘…ÁÑ•É}¥€ô€‘‘…ÁÑ•É%(€€€€€€€…‘…ÁÑ•É}Ù•ÉÍ¥½¸€ô€‘Ù•ÉÍ¥½¸(€€€€€€€¡½ÍÑ}½É}Ñ•¹…¹Ð€ô€‘¡½ÍÐ(€€€€€€€Í½ÕÉ•}É•™•É•¹”€ô€‘Í½ÕÉ”(€€€€€€€½‰Í•ÉÙ•‘}…Ð€ô€‘=‰Í•ÉÙ•‘Ð¹Q½U¹¥Ù•ÉÍ…±Q¥µ” ¤¹Q½MÑÉ¥¹œ ¼œ¤(€€€€€€€™É•Í¡}Õ¹Ñ¥°€ô€‘É•Í¡U¹Ñ¥°¹Q½U¹¥Ù•ÉÍ…±Q¥µ” ¤¹Q½MÑÉ¥¹œ ¼œ¤(€€€€€€€Í½ÕÉ•}­¥¹€ô€‘M½ÕÉ•-¥¹(€€€€€€€½¹¹•Ñ¥½¹}ÍÑ…Ñ”€ô€‘½¹¹•Ñ¥½¹MÑ…Ñ”(€€€€€€€±…¥µÌ€ô€‘±•…¹±…¥µÌ(€€€€€€€½¹Ñ•¹Ñ}É•…€ô€‘™…±Í”(€€€€€€€É•‘•¹Ñ¥…±Í}É•…€ô€‘™…±Í”(€€€€€€€½‰Í•ÉÙ…Ñ¥½¹}Í¡„ÈÔØ€ô€‘=‰Í•ÉÙ…Ñ¥½¹M¡„ÈÔØ(€€€€€€€µ¥ÍÍ¥½¹}…ÕÑ¡½É¥Ñä€ô€‘™…±Í”(€€€€€€€½Á•É…Ñ¥½¹Í}…ÕÑ¡½É¥Ñä€ô€‘™…±Í”(€€€€€€€…ÁÁÉ½Ù…±}…ÕÑ¡½É¥Ñä€ô€‘™…±Í”(€€€€€€€±•…É¹¥¹}ÁÉ½µ½Ñ¥½¹}…ÕÑ¡½É¥Ñä€ô€‘™…±Í”(€€€€€€€Í•¹Í¥Ñ¥Ù•}Ù…±Õ•Í}É•Ñ…¥¹•€ô€‘™…±Í”(€€€ô(€€€€‘É••¥ÁÐ¹É••¥ÁÑ}Í¡„ÈÔØ€ô•ÐµÉ­¼äÕ1•…É¹¥¹=‰©•Ñ!…Í €µY…±Õ”€¡•ÐµÉ­¼äÕ‘…ÁÑ•ÉI••¥ÁÑ!…Í¡5…Ñ•É¥…°€µI••¥ÁÐ€‘É••¥ÁÐ¤(€€€€‘µÕÑ•à€ô€‘¹Õ±°(€€€ÑÉäì(€€€€€€€€‘µÕÑ•à€ô¹Ñ•ÈµÉ­¼äÕ1•…É¹¥¹5ÕÑ•à€µMÑ…Ñ•I½½Ð€‘Á…Ñ¡Ì¹I½½Ð(€€€€€€€%¹¥Ñ¥…±¥é”µÉ­¼äÕ1•…É¹¥¹MÑ…Ñ”€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€€‘Ñ…É•Ð€ô)½¥¸µA…Ñ €‘Á…Ñ¡Ì¹‘…ÁÑ•ÉÌ€ ‘‘…ÁÑ•É%€¬€œ¹©Í½¸œ¤(€€€€€€€€‘Ñ•µÀ€ô€‘Ñ…É•Ð€¬€œ¹ÑµÀ´œ€¬mÕ¥‘tèé9•ÝÕ¥ ¤¹Q½MÑÉ¥¹œ 8œ¤(€€€€€€€mMåÍÑ•´¹%<¹¥±•tèé]É¥Ñ•±±Q•áÐ ‘Ñ•µÀ° ‘É••¥ÁÐð½¹Ù•ÉÑQ¼µ)Í½¸€µ•ÁÑ €ÄØ¤±mMåÍÑ•´¹Q•áÐ¹UQá¹½‘¥¹tèé¹•Ü ‘™…±Í”¤¤(€€€€€€€5½Ù”µ%Ñ•´€µ1¥Ñ•É…±A…Ñ €‘Ñ•µÀ€µ•ÍÑ¥¹…Ñ¥½¸€‘Ñ…É•Ð€µ½É”(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì‘…ÁÑ•É%ô‘‘…ÁÑ•É%ìIÕ¹Ñ¥µ•MÑ…Ñ”ô‘½¹¹•Ñ¥½¹MÑ…Ñ”ìÉ•Í¡U¹Ñ¥°ô‘É••¥ÁÐ¹™É•Í¡}Õ¹Ñ¥°ìI••¥ÁÑM¡„ÈÔØô‘É••¥ÁÐ¹É••¥ÁÑ}Í¡„ÈÔØìÕÑ¡½É¥Ñäô¹½¹”œô(€€€ô(€€€™¥¹…±±äìá¥ÐµÉ­¼äÕ1•…É¹¥¹5ÕÑ•à€µ5ÕÑ•à€‘µÕÑ•àô)ô()™Õ¹Ñ¥½¸•ÐµÉ­¼äÕ‘…ÁÑ•É…‰É¥MÑ…ÑÕÌì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘Á½±¥ä€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A½±¥ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð(€€€€‘É•ÍÕ±ÑÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑm½‰©•Ñutèé¹•Ü ¤(€€€™½É•… € ‘…‘…ÁÑ•È¥¸  ‘Á½±¥ä¹…‘…ÁÑ•ÉÌ¤¤ì(€€€€€€€€‘½‰Í•ÉÙ…Ñ¥½¸€ô€‘¹Õ±°(€€€€€€€€‘½‰Í•ÉÙ…Ñ¥½¹A…Ñ €ô)½¥¸µA…Ñ €‘Á…Ñ¡Ì¹‘…ÁÑ•ÉÌ€¡mÍÑÉ¥¹t‘…‘…ÁÑ•È¹¥€¬€œ¹©Í½¸œ¤(€€€€€€€¥˜€¡Q•ÍÐµA…Ñ €µ1¥Ñ•É…±A…Ñ €‘½‰Í•ÉÙ…Ñ¥½¹A…Ñ €µA…Ñ¡QåÁ”1•…˜¤ì(€€€€€€€€€€€ÑÉäì(€€€€€€€€€€€€€€€€‘Ù…±Õ”€ô•Ðµ½¹Ñ•¹Ð€µI…Ü€µ1¥Ñ•É…±A…Ñ €‘½‰Í•ÉÙ…Ñ¥½¹A…Ñ ð5¥É½Í½™Ð¹A½Ý•ÉM¡•±°¹UÑ¥±¥Ñåq½¹Ù•ÉÑÉ½´µ)Í½¸€µ…Ñ•-¥¹MÑÉ¥¹œ(€€€€€€€€€€€€€€€¥˜€¡mÍÑÉ¥¹t‘Ù…±Õ”¹…‘…ÁÑ•É}¥€µ•ÄmÍÑÉ¥¹t‘…‘…ÁÑ•È¹¥¤ì€‘½‰Í•ÉÙ…Ñ¥½¸ô‘Ù…±Õ”ô(€€€€€€€€€€€ô…Ñ ìô(€€€€€€€ô(€€€€€€€€‘Ù…±¥‘I••¥ÁÐ€ô€‘™…±Í”(€€€€€€€€‘¥¹Ñ•É¥ÑåY…±¥€ô€‘™…±Í”(€€€€€€€€‘™É•Í €ô€‘™…±Í”(€€€€€€€€‘½‰Í•ÉÙ•‘Ð€ô€œœ(€€€€€€€€‘™É•Í¡U¹Ñ¥°€ô€œœ(€€€€€€€€‘½¹¹•Ñ¥½¸€ô€Õ¹Ù•É¥™¥•œ(€€€€€€€€‘±…¥µÌ€ô  ¤(€€€€€€€¥˜€ ‘¹Õ±°€µ¹”€‘½‰Í•ÉÙ…Ñ¥½¸¤ì(€€€€€€€€€€€€‘µ¥ÍÍ¥¹œ€ô  ‘Á½±¥ä¹…‘…ÁÑ•É}É••¥ÁÐ¹É•ÅÕ¥É•‘}™¥•±‘Ìð]¡•É”µ=‰©•Ðì€‘¹Õ±°€µ•Ä€‘½‰Í•ÉÙ…Ñ¥½¸¹AM=‰©•Ð¹AÉ½Á•ÉÑ¥•ÍmmÍÑÉ¥¹t‘}t€µ½ÈmÍÑÉ¥¹tèé%Í9Õ±±=É]¡¥Ñ•MÁ…”¡mÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¸¡mÍÑÉ¥¹t‘|¤¤ô¤(€€€€€€€€€€€€‘Ù…±¥‘I••¥ÁÐ€ô€‘µ¥ÍÍ¥¹œ¹½Õ¹Ð€µ•Ä€À€µ…¹mÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹½‰Í•ÉÙ…Ñ¥½¹}Í¡„ÈÔØ€µµ…Ñ €ym„µ˜À´åuìØÑôœ(€€€€€€€€€€€¥˜€ ‘Ù…±¥‘I••¥ÁÐ€µ…¹€¡mÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹É••¥ÁÑ}­¥¹€µ¹”€…‘…ÁÑ•É}½‰Í•ÉÙ…Ñ¥½¸œ€µ½Èm‰½½±t‘½‰Í•ÉÙ…Ñ¥½¸¹½¹Ñ•¹Ñ}É•…€µ¹”€‘™…±Í”€µ½Èm‰½½±t‘½‰Í•ÉÙ…Ñ¥½¸¹É•‘•¹Ñ¥…±Í}É•…€µ¹”€‘™…±Í”¤¤ì€‘Ù…±¥‘I••¥ÁÐ€ô€‘™…±Í”ô(€€€€€€€€€€€¥˜€ ‘Ù…±¥‘I••¥ÁÐ¤ì(€€€€€€€€€€€€€€€€‘½‰Í•ÉÙ•‘Ð€ômÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹½‰Í•ÉÙ•‘}…Ð(€€€€€€€€€€€€€€€€‘™É•Í¡U¹Ñ¥°€ômÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹™É•Í¡}Õ¹Ñ¥°(€€€€€€€€€€€€€€€€‘™É•Í €ôÑÉäìm…Ñ•Q¥µ•=™™Í•ÑtèéA…ÉÍ” ‘™É•Í¡U¹Ñ¥°¤€µÐm…Ñ•Q¥µ•=™™Í•ÑtèéUÑ9½Üô…Ñ ì€‘™…±Í”ô(€€€€€€€€€€€€€€€¥˜€ ‘½‰Í•ÉÙ…Ñ¥½¸¹AM=‰©•Ð¹AÉ½Á•ÉÑ¥•Íl½¹¹•Ñ¥½¹}ÍÑ…Ñ”t¤ì€‘½¹¹•Ñ¥½¸€ômÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹½¹¹•Ñ¥½¹}ÍÑ…Ñ”ô(€€€€€€€€€€€€€€€•±Í•¥˜€ ‘½‰Í•ÉÙ…Ñ¥½¸¹AM=‰©•Ð¹AÉ½Á•ÉÑ¥•Íl½¹¹•Ñ¥½¸t¤ì€‘½¹¹•Ñ¥½¸€ômÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹½¹¹•Ñ¥½¸ô(€€€€€€€€€€€€€€€•±Í”ì€‘½¹¹•Ñ¥½¸€ô€½‰Í•ÉÙ•‘}µ•Ñ…‘…Ñ„œô(€€€€€€€€€€€€€€€€‘±…¥µÌ€ô  ‘½‰Í•ÉÙ…Ñ¥½¸¹±…¥µÌð½É… µ=‰©•ÐìmÍÑÉ¥¹t‘|ô¤(€€€€€€€€€€€€€€€¥˜€ ‘±…¥µÌ¹½Õ¹Ð€µ±Ð€Ä€µ½È  ‘±…¥µÌð]¡•É”µ=‰©•Ðì€‘|€µ¹½Ñ¥¸  ‘…‘…ÁÑ•È¹…±±½Ý•‘}±…¥µÌ¤ô¤¹½Õ¹Ð€µÐ€À¤ì€‘Ù…±¥‘I••¥ÁÐô‘™…±Í”ì€‘¥¹Ñ•É¥ÑåY…±¥ô‘™…±Í”ô(€€€€€€€€€€€€€€€¥˜€ ‘½‰Í•ÉÙ…Ñ¥½¸¹AM=‰©•Ð¹AÉ½Á•ÉÑ¥•ÍlÉ••¥ÁÑ}Í¡„ÈÔØt€µ…¹mÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹É••¥ÁÑ}Í¡„ÈÔØ€µµ…Ñ €ym„µ˜À´åuìØÑôœ¤ì(€€€€€€€€€€€€€€€€€€€ÑÉäì€‘¥¹Ñ•É¥ÑåY…±¥€ômÍÑÉ¥¹t‘½‰Í•ÉÙ…Ñ¥½¸¹É••¥ÁÑ}Í¡„ÈÔØ€µ•Ä€¡•ÐµÉ­¼äÕ1•…É¹¥¹=‰©•Ñ!…Í €µY…±Õ”€¡•ÐµÉ­¼äÕ‘…ÁÑ•ÉI••¥ÁÑ!…Í¡5…Ñ•É¥…°€µI••¥ÁÐ€‘½‰Í•ÉÙ…Ñ¥½¸¤¤ô…Ñ ì€‘¥¹Ñ•É¥ÑåY…±¥€ô€‘™…±Í”ô(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô(€€€€€€€ô(€€€€€€€€‘ÉÕ¹Ñ¥µ•MÑ…Ñ”€ô¥˜€ µ¹½Ð€‘Ù…±¥‘I••¥ÁÐ¤ì€Õ¹…Ù…¥±…‰±”œô•±Í•¥˜€ µ¹½Ð€‘¥¹Ñ•É¥ÑåY…±¥¤ì€Õ¹Ù•É¥™¥•‘}¥¹Ñ•É¥Ñäœô•±Í•¥˜€ µ¹½Ð€‘™É•Í ¤ì€Õ¹…Ù…¥±…‰±•}ÍÑ…±”œô•±Í”ì€½‰Í•ÉÙ•‘}™É•Í œô(€€€€€€€€‘É•ÍÕ±ÑÌ¹‘¡mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€€€€€…‘…ÁÑ•É}¥€ômÍÑÉ¥¹t‘…‘…ÁÑ•È¹¥(€€€€€€€€€€€‘¥ÍÁ±…å}¹…µ”€ômÍÑÉ¥¹t‘…‘…ÁÑ•È¹‘¥ÍÁ±…å}¹…µ”(€€€€€€€€€€€¹…Ñ¥Ù•}‰½Õ¹‘…Éä€ômÍÑÉ¥¹t‘…‘…ÁÑ•È¹¹…Ñ¥Ù•}‰½Õ¹‘…Éä(€€€€€€€€€€€½¹™¥ÕÉ•‘}ÍÑ…Ñ”€ômÍÑÉ¥¹t‘…‘…ÁÑ•È¹½¹™¥ÕÉ•‘}ÍÑ…Ñ”(€€€€€€€€€€€ÉÕ¹Ñ¥µ•}ÍÑ…Ñ”€ô€‘ÉÕ¹Ñ¥µ•MÑ…Ñ”(€€€€€€€€€€€½¹¹•Ñ¥½¹}±…¥´€ô€‘½¹¹•Ñ¥½¸(€€€€€€€€€€€±…¥µÌ€ô€‘±…¥µÌ(€€€€€€€€€€€½‰Í•ÉÙ•‘}…Ð€ô€‘½‰Í•ÉÙ•‘Ð(€€€€€€€€€€€™É•Í¡}Õ¹Ñ¥°€ô€‘™É•Í¡U¹Ñ¥°(€€€€€€€€€€€½‰Í•ÉÙ…Ñ¥½¹}Á…Ñ €ô€‘½‰Í•ÉÙ…Ñ¥½¹A…Ñ (€€€€€€€€€€€É••¥ÁÑ}¥¹Ñ•É¥Ñå}Ù…±¥€ô€‘¥¹Ñ•É¥ÑåY…±¥(€€€€€€€€€€€•™™•Ð€ô€ÁÉ½Á½Í…±}½¹±äœ(€€€€€€€€€€€…ÕÑ¡½É¥Ñä€ô€¹½¹”œ(€€€€€€€ô¤(€€€ô(€€€É•ÑÕÉ¸€‘É•ÍÕ±ÑÌ¹Q½ÉÉ…ä ¤)ô()™Õ¹Ñ¥½¸UÁ‘…Ñ”µÉ­¼äÕ1½…±‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¹Ìì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€€‘¹½Ü€ôm…Ñ•Q¥µ•=™™Í•ÑtèéUÑ9½Ü(€€€€‘Õ¹Ñ¥°€ô€‘¹½Ü¹‘‘5¥¹ÕÑ•Ì ÄÔ¤(€€€€‘É••¥ÁÑÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑm½‰©•Ñutèé¹•Ü ¤(€€€€‘Õ¹…Ù…¥±…‰±”€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑmÍÑÉ¥¹utèé¹•Ü ¤((€€€™Õ¹Ñ¥½¸•Ðµ=‰Í•ÉÙ…Ñ¥½¹¥•ÍÐì(€€€€€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥t‘Y…±Õ”¤(€€€€€€€É•ÑÕÉ¸•ÐµÉ­¼äÕ1•…É¹¥¹=‰©•Ñ!…Í €µY…±Õ”€‘Y…±Õ”(€€€ô((€€€ÑÉäì(€€€€€€€€‘ÁÉ½•ÍÌ€ô•ÐµAÉ½•ÍÌ€µ9…µ”€=Á•¹±…Ü¹QÉ…ä¹]¥¹U$œ€µÉÉ½ÉÑ¥½¸MÑ½ÀðM•±•Ðµ=‰©•Ð€µ¥ÉÍÐ€Ä(€€€€€€€€‘Á…Ñ €ô€‘ÁÉ½•ÍÌ¹5…¥¹5½‘Õ±”¹¥±•9…µ”(€€€€€€€€‘Í¥¹…ÑÕÉ”€ô€¡•ÐµÕÑ¡•¹Ñ¥½‘•M¥¹…ÑÕÉ”€µ1¥Ñ•É…±A…Ñ €‘Á…Ñ ¤¹MÑ…ÑÕÌ(€€€€€€€€‘±¥ÍÑ•¹•ÉÌ€ô ¡•Ðµ9•ÑQA½¹¹•Ñ¥½¸€µMÑ…Ñ”1¥ÍÑ•¸€µ1½…±A½ÉÐ€ÄàÜàä€µÉÉ½ÉÑ¥½¸MÑ½Àð]¡•É”µ=‰©•Ðì€‘|¹1½…±‘‘É•ÍÌ€µ¥¸  œÄÈÜ¸À¸À¸Äœ°œèèÄœ¤ô¤(€€€€€€€€‘±…¥µÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑmÍÑÉ¥¹utèé¹•Ü ¤ì€‘±…¥µÌ¹‘ ÁÉ½•ÍÍ}ÉÕ¹¹¥¹œœ¤(€€€€€€€¥˜€ ‘Í¥¹…ÑÕÉ”€µ•Ä€Y…±¥œ¤ì€‘±…¥µÌ¹‘ Í¥¹•‘}‰¥¹…Éäœ¤ô(€€€€€€€¥˜€ ‘±¥ÍÑ•¹•ÉÌ¹½Õ¹Ð€µÐ€À¤ì€‘±…¥µÌ¹‘ ±½½Á‰…­}…Ñ•Ý…å}±¥ÍÑ•¹¥¹œœ¤ô(€€€€€€€€‘•Ù¥‘•¹”€ôm½É‘•É•‘uìÁÉ½‘ÕÐô=Á•¹±…Ü½µÁ…¹¥½¸œìÙ•ÉÍ¥½¸õmÍÑÉ¥¹t‘ÁÉ½•ÍÌ¹5…¥¹5½‘Õ±”¹¥±•Y•ÉÍ¥½¹%¹™¼¹AÉ½‘ÕÑY•ÉÍ¥½¸ìÍ¥¹…ÑÕÉ”õmÍÑÉ¥¹t‘Í¥¹…ÑÕÉ”ì±½½Á‰…­}±¥ÍÑ•¹•É}½Õ¹Ðô‘±¥ÍÑ•¹•ÉÌ¹½Õ¹Ðô(€€€€€€€€‘É••¥ÁÑÌ¹‘ ¡I•¥ÍÑ•ÈµÉ­¼äÕ‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¸€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð€µ‘…ÁÑ•É%½Á•¹±…Ý}½µÁ…¹¥½¸€µ‘…ÁÑ•ÉY•ÉÍ¥½¸€¡mÍÑÉ¥¹t‘ÁÉ½•ÍÌ¹5…¥¹5½‘Õ±”¹¥±•Y•ÉÍ¥½¹%¹™¼¹AÉ½‘ÕÑY•ÉÍ¥½¸¤€µ!½ÍÑ=ÉQ•¹…¹Ð€‘•¹Øé=5AUQI95€µM½ÕÉ•-¥¹½µÁ…¹¥½¹}‘¥…¹½ÍÑ¥Í}µ•Ñ…‘…Ñ„€µM½ÕÉ•I•™•É•¹”€±½…°½¹Ñ•¹Ðµ™É•”Í¥¹•µÁÉ½•ÍÌ…¹±½½Á‰…¬µ±¥ÍÑ•¹•È½‰Í•ÉÙ…Ñ¥½¸œ€µ±…¥µÌ€‘±…¥µÌ¹Q½ÉÉ…ä ¤€µ=‰Í•ÉÙ•‘Ð€‘¹½Ü€µÉ•Í¡U¹Ñ¥°€‘Õ¹Ñ¥°€µ=‰Í•ÉÙ…Ñ¥½¹M¡„ÈÔØ€¡•Ðµ=‰Í•ÉÙ…Ñ¥½¹¥•ÍÐ€µY…±Õ”€‘•Ù¥‘•¹”¤€µ½¹¹•Ñ¥½¹MÑ…Ñ”€¡¥˜ ‘±¥ÍÑ•¹•ÉÌ¹½Õ¹Ð€µÐ€À¥ì½‰Í•ÉÙ•‘}½¹¹•Ñ•õ•±Í•ì½‰Í•ÉÙ•‘}ÁÉ•Í•¹Ðô¤¤¤(€€€ô(€€€…Ñ ì€‘Õ¹…Ù…¥±…‰±”¹‘ ½Á•¹±…Ý}½µÁ…¹¥½¸œ¤ô((€€€ÑÉäì(€€€€€€€€‘Á…­…”€ô•ÐµÁÁáA…­…”€µ9…µ”€5¥É½Í½™Ð¹½Á¥±½Ðœ€µÉÉ½ÉÑ¥½¸MÑ½ÀðM•±•Ðµ=‰©•Ð€µ¥ÉÍÐ€Ä(€€€€€€€¥˜€ ‘¹Õ±°€µ•Ä€‘Á…­…”¤ìÑ¡É½Ü€Á…­…”µ¥ÍÍ¥¹œœô(€€€€€€€€‘ÁÉ½•ÍÍ•Ì€ô ¡•ÐµAÉ½•ÍÌ€µ9…µ”€µÍ½Á¥±½Ðœ€µÉÉ½ÉÑ¥½¸M¥±•¹Ñ±å½¹Ñ¥¹Õ”¤(€€€€€€€€‘±…¥µÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑmÍÑÉ¥¹utèé¹•Ü ¤ì€‘±…¥µÌ¹‘ Á…­…•}ÁÉ•Í•¹Ðœ¤(€€€€€€€¥˜€ ‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ð€µÐ€À¤ì€‘±…¥µÌ¹‘ ÁÉ½•ÍÍ}ÉÕ¹¹¥¹œœ¤ô(€€€€€€€€‘Í¥¹…ÑÕÉ•Y…±¥€ô€‘™…±Í”(€€€€€€€¥˜€ ‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ð€µÐ€À¤ìÑÉäì€‘Í¥¹…ÑÕÉ•Y…±¥€ô€¡•ÐµÕÑ¡•¹Ñ¥½‘•M¥¹…ÑÕÉ”€µ1¥Ñ•É…±A…Ñ €‘ÁÉ½•ÍÍ•ÍlÁt¹5…¥¹5½‘Õ±”¹¥±•9…µ”¤¹MÑ…ÑÕÌ€µ•Ä€Y…±¥œô…Ñ ìôô(€€€€€€€¥˜€ ‘Í¥¹…ÑÕÉ•Y…±¥¤ì€‘±…¥µÌ¹‘ Á…­…•}Í¥¹…ÑÕÉ•}Ù…±¥œ¤ô(€€€€€€€€‘•Ù¥‘•¹”€ôm½É‘•É•‘uìÁ…­…”õmÍÑÉ¥¹t‘Á…­…”¹9…µ”ìÙ•ÉÍ¥½¸õmÍÑÉ¥¹t‘Á…­…”¹Y•ÉÍ¥½¸ìÍ¥¹…ÑÕÉ•}­¥¹õmÍÑÉ¥¹t‘Á…­…”¹M¥¹…ÑÕÉ•-¥¹ìÁÉ½•ÍÍ}½Õ¹Ðô‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ðì•á•ÕÑ…‰±•}Í¥¹…ÑÕÉ•}Ù…±¥ô‘Í¥¹…ÑÕÉ•Y…±¥ô(€€€€€€€€‘É••¥ÁÑÌ¹‘ ¡I•¥ÍÑ•ÈµÉ­¼äÕ‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¸€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð€µ‘…ÁÑ•É%µ¥É½Í½™Ñ}½Á¥±½Ð€µ‘…ÁÑ•ÉY•ÉÍ¥½¸€¡mÍÑÉ¥¹t‘Á…­…”¹Y•ÉÍ¥½¸¤€µ!½ÍÑ=ÉQ•¹…¹Ð€‘•¹Øé=5AUQI95€µM½ÕÉ•-¥¹ÁÉ½•ÍÍ}…¹‘}Á…­…•}µ•Ñ…‘…Ñ„€µM½ÕÉ•I•™•É•¹”€±½…°½¹Ñ•¹Ðµ™É•”Á…­…”…¹ÁÉ½•ÍÌ½‰Í•ÉÙ…Ñ¥½¸œ€µ±…¥µÌ€‘±…¥µÌ¹Q½ÉÉ…ä ¤€µ=‰Í•ÉÙ•‘Ð€‘¹½Ü€µÉ•Í¡U¹Ñ¥°€‘Õ¹Ñ¥°€µ=‰Í•ÉÙ…Ñ¥½¹M¡„ÈÔØ€¡•Ðµ=‰Í•ÉÙ…Ñ¥½¹¥•ÍÐ€µY…±Õ”€‘•Ù¥‘•¹”¤€µ½¹¹•Ñ¥½¹MÑ…Ñ”½‰Í•ÉÙ•‘}ÁÉ•Í•¹Ð¤¤(€€€ô(€€€…Ñ ì€‘Õ¹…Ù…¥±…‰±”¹‘ µ¥É½Í½™Ñ}½Á¥±½Ðœ¤ô((€€€ÑÉäì(€€€€€€€€‘Á…­…”€ô•ÐµÁÁáA…­…”€µ9…µ”€=Á•¹$¹¡…ÑAPµ•Í­Ñ½Àœ€µÉÉ½ÉÑ¥½¸MÑ½ÀðM•±•Ðµ=‰©•Ð€µ¥ÉÍÐ€Ä(€€€€€€€¥˜€ ‘¹Õ±°€µ•Ä€‘Á…­…”¤ìÑ¡É½Ü€Á…­…”µ¥ÍÍ¥¹œœô(€€€€€€€€‘ÁÉ½•ÍÍ•Ì€ô ¡•ÐµAÉ½•ÍÌð]¡•É”µ=‰©•Ðì€‘|¹AÉ½•ÍÍ9…µ”€µ•Ä€¡…ÑAP±…ÍÍ¥Œœô¤(€€€€€€€€‘±…¥µÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑmÍÑÉ¥¹utèé¹•Ü ¤ì€‘±…¥µÌ¹‘ Á…­…•}ÁÉ•Í•¹Ðœ¤ì€‘±…¥µÌ¹‘ Á…­…•}¥‘•¹Ñ¥Ñå}½‰Í•ÉÙ•œ¤(€€€€€€€¥˜€ ‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ð€µÐ€À¤ì€‘±…¥µÌ¹‘ ÁÉ½•ÍÍ}ÉÕ¹¹¥¹œœ¤ô(€€€€€€€€‘•Ù¥‘•¹”€ôm½É‘•É•‘uìÁ…­…”õmÍÑÉ¥¹t‘Á…­…”¹9…µ”ìÙ•ÉÍ¥½¸õmÍÑÉ¥¹t‘Á…­…”¹Y•ÉÍ¥½¸ìÍ¥¹…ÑÕÉ•}­¥¹õmÍÑÉ¥¹t‘Á…­…”¹M¥¹…ÑÕÉ•-¥¹ìÁÉ½•ÍÍ}½Õ¹Ðô‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ðô(€€€€€€€€‘É••¥ÁÑÌ¹‘ ¡I•¥ÍÑ•ÈµÉ­¼äÕ‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¸€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð€µ‘…ÁÑ•É%¡…ÑÁÐ€µ‘…ÁÑ•ÉY•ÉÍ¥½¸€¡mÍÑÉ¥¹t‘Á…­…”¹Y•ÉÍ¥½¸¤€µ!½ÍÑ=ÉQ•¹…¹Ð€‘•¹Øé=5AUQI95€µM½ÕÉ•-¥¹ÁÉ½•ÍÍ}…¹‘}Á…­…•}µ•Ñ…‘…Ñ„€µM½ÕÉ•I•™•É•¹”€±½…°½¹Ñ•¹Ðµ™É•”Á…­…”…¹ÁÉ½•ÍÌ½‰Í•ÉÙ…Ñ¥½¸œ€µ±…¥µÌ€‘±…¥µÌ¹Q½ÉÉ…ä ¤€µ=‰Í•ÉÙ•‘Ð€‘¹½Ü€µÉ•Í¡U¹Ñ¥°€‘Õ¹Ñ¥°€µ=‰Í•ÉÙ…Ñ¥½¹M¡„ÈÔØ€¡•Ðµ=‰Í•ÉÙ…Ñ¥½¹¥•ÍÐ€µY…±Õ”€‘•Ù¥‘•¹”¤€µ½¹¹•Ñ¥½¹MÑ…Ñ”½‰Í•ÉÙ•‘}ÁÉ•Í•¹Ð¤¤(€€€ô(€€€…Ñ ì€‘Õ¹…Ù…¥±…‰±”¹‘ ¡…ÑÁÐœ¤ô((€€€ÑÉäì(€€€€€€€€‘Á…­…•Ì€ô ¡•ÐµÁÁáA…­…”ð]¡•É”µ=‰©•Ðì€‘|¹9…µ”€µ¥¸  =Á•¹$¹½‘•àœ°=Á•¹$¹½‘•á	•Ñ„œ¤ô¤(€€€€€€€¥˜€ ‘Á…­…•Ì¹½Õ¹Ð€µ±Ð€Ä¤ìÑ¡É½Ü€Á…­…”µ¥ÍÍ¥¹œœô(€€€€€€€€‘ÁÉ½•ÍÍ•Ì€ô ¡•ÐµAÉ½•ÍÌð]¡•É”µ=‰©•Ðì€‘|¹AÉ½•ÍÍ9…µ”€µ¥¸  ½‘•àœ°½‘•àµ½‘”µµ½‘”µ¡½ÍÐœ°¡…ÑAP€¡	•Ñ„¤œ¤ô¤(€€€€€€€€‘±…¥µÌ€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑmÍÑÉ¥¹utèé¹•Ü ¤ì€‘±…¥µÌ¹‘ Á…­…•}ÁÉ•Í•¹Ðœ¤ì€‘±…¥µÌ¹‘ µ…¹Õ…±}¡…¹‘½™™}½¹±äœ¤(€€€€€€€¥˜€ ‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ð€µÐ€À¤ì€‘±…¥µÌ¹‘ ÁÉ½•ÍÍ}ÉÕ¹¹¥¹œœ¤ô(€€€€€€€€‘Ù…±¥‘…Ñ¥½¹A…Ñ €ô)½¥¸µA…Ñ €‘•¹ØéUMIAI=%1€œ¹½‘•áqÁ•ÑÍq…É­¼´äÕqÙ…±¥‘…Ñ¥½¸¹©Í½¸œ(€€€€€€€€‘Á•ÑY…±¥€ô€‘™…±Í”(€€€€€€€¥˜€¡Q•ÍÐµA…Ñ €µ1¥Ñ•É…±A…Ñ €‘Ù…±¥‘…Ñ¥½¹A…Ñ €µA…Ñ¡QåÁ”1•…˜¤ìÑÉäì€‘Á•ÑY…±¥€ôm‰½½±t ¡•Ðµ½¹Ñ•¹Ð€µI…Ü€µ1¥Ñ•É…±A…Ñ €‘Ù…±¥‘…Ñ¥½¹A…Ñ ð½¹Ù•ÉÑÉ½´µ)Í½¸¤¹½¬¤ô…Ñ ìôô(€€€€€€€¥˜€ ‘Á•ÑY…±¥¤ì€‘±…¥µÌ¹‘ …É­½}Á•Ñ}Ù…±¥‘…Ñ•œ¤ô(€€€€€€€€‘Ù•ÉÍ¥½¹Ì€ô  ‘Á…­…•Ìð½É… µ=‰©•ÐìmÍÑÉ¥¹t‘|¹Y•ÉÍ¥½¸ô¤(€€€€€€€€‘•Ù¥‘•¹”€ôm½É‘•É•‘uìÁ…­…•Ìõ  ‘Á…­…•Ìð½É… µ=‰©•ÐìmÍÑÉ¥¹t‘|¹9…µ”ô¤ìÙ•ÉÍ¥½¹Ìô‘Ù•ÉÍ¥½¹ÌìÁÉ½•ÍÍ}½Õ¹Ðô‘ÁÉ½•ÍÍ•Ì¹½Õ¹Ðì…É­½}Á•Ñ}Ù…±¥‘…Ñ•ô‘Á•ÑY…±¥ì¡…¹‘½™˜ôµ…¹Õ…±}½¹±äœô(€€€€€€€€‘É••¥ÁÑÌ¹‘ ¡I•¥ÍÑ•ÈµÉ­¼äÕ‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¸€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð€µ‘…ÁÑ•É%½‘•à€µ‘…ÁÑ•ÉY•ÉÍ¥½¸€ ‘Ù•ÉÍ¥½¹Ì€µ©½¥¸€œ¬œ¤€µ!½ÍÑ=ÉQ•¹…¹Ð€‘•¹Øé=5AUQI95€µM½ÕÉ•-¥¹¡½ÍÑ}½¹Ñ•áÑ}µ•Ñ…‘…Ñ„€µM½ÕÉ•I•™•É•¹”€±½…°½¹Ñ•¹Ðµ™É•”¡½ÍÐÁ…­…”°ÁÉ½•ÍÌ°…¹Á•ÐµÙ…±¥‘…Ñ¥½¸½‰Í•ÉÙ…Ñ¥½¸œ€µ±…¥µÌ€‘±…¥µÌ¹Q½ÉÉ…ä ¤€µ=‰Í•ÉÙ•‘Ð€‘¹½Ü€µÉ•Í¡U¹Ñ¥°€‘Õ¹Ñ¥°€µ=‰Í•ÉÙ…Ñ¥½¹M¡„ÈÔØ€¡•Ðµ=‰Í•ÉÙ…Ñ¥½¹¥•ÍÐ€µY…±Õ”€‘•Ù¥‘•¹”¤€µ½¹¹•Ñ¥½¹MÑ…Ñ”½‰Í•ÉÙ•‘}ÁÉ•Í•¹Ð¤¤(€€€ô(€€€…Ñ ì€‘Õ¹…Ù…¥±…‰±”¹‘ ½‘•àœ¤ô((€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€=‰Í•ÉÙ•‘Ð€ô€‘¹½Ü¹Q½MÑÉ¥¹œ ¼œ¤(€€€€€€€É•Í¡U¹Ñ¥°€ô€‘Õ¹Ñ¥°¹Q½MÑÉ¥¹œ ¼œ¤(€€€€€€€I••¥ÁÑ½Õ¹Ð€ô€‘É••¥ÁÑÌ¹½Õ¹Ð(€€€€€€€I••¥ÁÑÌ€ô€‘É••¥ÁÑÌ¹Q½ÉÉ…ä ¤(€€€€€€€U¹…Ù…¥±…‰±”€ô€‘Õ¹…Ù…¥±…‰±”¹Q½ÉÉ…ä ¤(€€€€€€€½¹Ñ•¹ÑI•…€ô€‘™…±Í”(€€€€€€€É•‘•¹Ñ¥…±ÍI•…€ô€‘™…±Í”(€€€€€€€ÕÑ¡½É¥Ñä€ô€¹½¹”œ(€€€ô)ô()™Õ¹Ñ¥½¸Q•ÍÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹¡…¥¸ì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€ÑÉäì(€€€€€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•ÑuìY…±¥ô‘É•Á±…ä¹Y…±¥ìÉÉ½ÉÌô‘É•Á±…ä¹ÉÉ½ÉÌìÙ•¹Ñ½Õ¹Ðô‘É•Á±…ä¹Ù•¹Ñ½Õ¹Ðì!•…‘!…Í ô‘É•Á±…ä¹!•…‘!…Í ìAÉ½©•Ñ¥½¹%ÍÕÑ¡½É¥Ñäô‘™…±Í”ì1¥µ¥Ñ…Ñ¥½¸ôM!´ÈÔØ¡…¥¹¥¹œ‘•Ñ•ÑÌ½É‘¥¹…Éä•‘¥ÑÌ‰ÕÐ¥Ì¹½Ð•áÑ•É¹…±±ä…¹¡½É•……¥¹ÍÐ„Í…µ”µÕÍ•È™Õ±°É•ÝÉ¥Ñ”½È±•…¸Ñ…¥°ÑÉÕ¹…Ñ¥½¸¸œô(€€€ô(€€€…Ñ ìÉ•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•ÑuìY…±¥ô‘™…±Í”ìÉÉ½ÉÌõ  ‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”¤ìÙ•¹Ñ½Õ¹ÐôÀì!•…‘!…Í ôœœìAÉ½©•Ñ¥½¹%ÍÕÑ¡½É¥Ñäô‘™…±Í”ì1¥µ¥Ñ…Ñ¥½¸ôY•É¥™¥…Ñ¥½¸™…¥±•±½Í•¸œôô)ô()™Õ¹Ñ¥½¸•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹MÑ…ÑÕÌì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘Á½±¥ä€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A½±¥ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð(€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€‘½Á•¸€ô  ‘É•Á±…ä¹å±•Ìð]¡•É”µ=‰©•Ðì€‘|¹ÍÑ…ÑÕÌ€µ•Ä€…Ñ¥Ù”œô¤(€€€€‘…Ñ¥Ù”€ô¥˜€ ‘½Á•¸¹½Õ¹Ð€µ•Ä€Ä¤ì€‘½Á•¹lÁtô•±Í”ì€‘¹Õ±°ô(€€€mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€%¹¥Ñ¥…±¥é•€ôQ•ÍÐµA…Ñ €µ1¥Ñ•É…±A…Ñ €‘Á…Ñ¡Ì¹1•‘•È€µA…Ñ¡QåÁ”1•…˜(€€€€€€€¡…¥¹Y…±¥€ôm‰½½±t‘É•Á±…ä¹Y…±¥(€€€€€€€¡…¥¹ÉÉ½ÉÌ€ô  ‘É•Á±…ä¹ÉÉ½ÉÌ¤(€€€€€€€Ù•¹Ñ½Õ¹Ð€ôm¥¹Ñt‘É•Á±…ä¹Ù•¹Ñ½Õ¹Ð(€€€€€€€!•…‘!…Í €ômÍÑÉ¥¹t‘É•Á±…ä¹!•…‘!…Í (€€€€€€€å±•½Õ¹Ð€ô  ‘É•Á±…ä¹å±•Ì¤¹½Õ¹Ð(€€€€€€€=Á•¹å±•½Õ¹Ð€ô€‘½Á•¸¹½Õ¹Ð(€€€€€€€Ñ¥Ù•å±”€ô¥˜€ ‘¹Õ±°€µ•Ä€‘…Ñ¥Ù”¤ì€‘¹Õ±°ô•±Í”ìmÁÍÕÍÑ½µ½‰©•Ñt¡½¹Ù•ÉÑQ¼µÉ­¼äÕ1•…É¹¥¹AÉ½©•Ñ¥½¹å±”€µå±”€‘…Ñ¥Ù”¤ô(€€€€€€€å±•Ì€ô  ‘É•Á±…ä¹å±•Ìð½É… µ=‰©•ÐìmÁÍÕÍÑ½µ½‰©•Ñt¡½¹Ù•ÉÑQ¼µÉ­¼äÕ1•…É¹¥¹AÉ½©•Ñ¥½¹å±”€µå±”€‘|¤ô¤(€€€€€€€‘…ÁÑ•ÉÌ€ô ¡•ÐµÉ­¼äÕ‘…ÁÑ•É…‰É¥MÑ…ÑÕÌ€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð¤(€€€€€€€‘…ÁÑ•ÉÕÑ¡½É¥Ñä€ô€¹½¹”œ(€€€€€€€5½‘”€ô€Í¡…‘½Ý}±•…É¹¥¹œœ(€€€€€€€áÁ±½É…Ñ¥½¹…ÁA•É•¹Ð€ô€ÈÔ(€€€€€€€AÉ½Ñ•Ñ•‘á•ÕÑ¥½¹Ù¥‘•¹•A•É•¹Ð€ô€ÜÔ(€€€€€€€AÉ½©•Ñ¥½¹%ÍÕÑ¡½É¥Ñä€ô€‘™…±Í”(€€€€€€€AÉ½µ½Ñ¥½¹•™…Õ±Ð€ô€ÁÉ½Á½Í•‘}½¹±äœ(€€€€€€€á•ÕÑ¥½¹ÕÑ¡½É¥Ñä€ô€½Á•É…Ñ¥½¹Í}ÙÁ}½¹±äœ(€€€ô)ô()áÁ½ÉÐµ5½‘Õ±•5•µ‰•È€µÕ¹Ñ¥½¸•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A…Ñ¡Ì°•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹A½±¥ä°9•ÜµÉ­¼äÕ•¥Í¥½¹å±”°‘µÉ­¼äÕ•¥Í¥½¹I•½É°M•ÐµÉ­¼äÕ1•ÍÍ½¹…¹‘¥‘…Ñ•I•Ù¥•Ü°±½Í”µÉ­¼äÕ•¥Í¥½¹å±”°I•¥ÍÑ•ÈµÉ­¼äÕ‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¸°•ÐµÉ­¼äÕ‘…ÁÑ•É…‰É¥MÑ…ÑÕÌ°UÁ‘…Ñ”µÉ­¼äÕ1½…±‘…ÁÑ•É=‰Í•ÉÙ…Ñ¥½¹Ì°Q•ÍÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹¡…¥¸°•ÐµÉ­¼äÕ•¥Í¥½¹1•…É¹¥¹MÑ…ÑÕÌ