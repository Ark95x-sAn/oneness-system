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
        MissionAdapterObservations = Join-Path $core.StateDir 'mission-control\adapter-observations'
    }
}

function Get-Arko95DecisionLearningPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $paths = Get-Arko95DecisionLearningPaths -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $paths.Policy -PathType Leaf)) { throw 'Decision Learning policy is missing.' }
    $policy = Get-Content -Raw -LiteralPath $paths.Policy | ConvertFrom-Json -DateKind String
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
        $events.Add(($line | ConvertFrom-Json -DateKind String))
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
        throw 'A le×M9ÒÚ$z{-®éÜj×6†VÖ÷fW'6–öâÒ¢&V6V—Eö¶–æBÒvFFW%öö'6W'fF–öâp¢FFW%ö–BÒDFFW$–@¢FFW%÷fW'6–öâÒGfW'6–öà¢†÷7Eö÷%÷FVæçBÒF†÷7@¢6÷W&6U÷&VfW&Væ6RÒG6÷W&6P¢ö'6W'fVEöBÒDö'6W'fVDBåFõVæ—fW'6ÅF–ÖR‚’åFõ7G&–ær‚vòr¢g&W6…÷VçF–ÂÒDg&W6…VçF–ÂåFõVæ—fW'6ÅF–ÖR‚’åFõ7G&–ær‚vòr¢6÷W&6Uö¶–æBÒE6÷W&6T¶–æ@¢6öææV7F–öå÷7FFRÒD6öææV7F–öå7FFP¢6Æ–×2ÒF6ÆVä6Æ–×0¢6öçFVçE÷&VBÒFfÇ6P¢7&VFVçF–Ç5÷&VBÒFfÇ6P¢ö'6W'fF–öå÷6†#SbÒDö'6W'fF–öå6†#S`¢Ö—76–öåöWF†÷&—G’ÒFfÇ6P¢÷W&F–öç5öWF†÷&—G’ÒFfÇ6P¢&÷fÅöWF†÷&—G’ÒFfÇ6P¢ÆV&æ–æu÷&öÖ÷F–öåöWF†÷&—G’ÒFfÇ6P¢6Vç6—F—fU÷fÇVW5÷&WF–æVBÒFfÇ6P¢Ð¢G&V6V—Bç&V6V—E÷6†#SbÒvWBÔ&¶ó“TÆV&æ–ætö&¦V7D†6‚ÕfÇVR„vWBÔ&¶ó“TFFW%&V6V—D†6„ÖFW&–ÂÕ&V6V—BG&V6V—B¢F×WFW‚ÒFçVÆÀ¢G'’°¢F×WFW‚ÒVçFW"Ô&¶ó“TÆV&æ–æt×WFW‚Õ7FFU&ö÷BGF‡2å&ö÷@¢–æ—F–Æ—¦RÔ&¶ó“TÆV&æ–æu7FFRÕF‡2GF‡0¢GF&vWBÒ¦ö–âÕF‚GF‡2äFFW'2‚DFFW$–B²ræ§6öâr¢GFV×ÒGF&vWB²rçF×Òr²¶wV–EÓ£¤æWtwV–B‚’åFõ7G&–ær‚târ¢µ7—7FVÒä”òäf–ÆUÓ£¥w&—FTÆÅFW‡B‚GFV×Â‚G&V6V—BÂ6öçfW'EFòÔ§6öâÔFWF‚b’Åµ7—7FVÒåFW‡BåUDc„Væ6öF–æuÓ£¦æWr‚FfÇ6R’¢Ö÷fRÔ—FVÒÔÆ—FW&ÅF‚GFV×ÔFW7F–æF–öâGF&vWBÔf÷&6P¢&WGW&â·67W7FöÖö&¦V7EÔ²FFW$–CÒDFFW$–C²'VçF–ÖU7FFSÒD6öææV7F–öå7FFS²g&W6…VçF–ÃÒG&V6V—Bæg&W6…÷VçF–Ã²&V6V—E6†#ScÒG&V6V—Bç&V6V—E÷6†#Sc²WF†÷&—G“ÒvæöæRrÐ¢Ð¢f–æÆÇ’²W†—BÔ&¶ó“TÆV&æ–æt×WFW‚Ô×WFW‚F×WFW‚Ð§Ð ¦gVæ7F–öâvWBÔ&¶ó“TFFW$f'&–57FGW2°¢´6ÖFÆWD&–æF–ær‚•Ð¢&Ò…µ&ÖWFW"„ÖæFF÷'’•Õ·7G&–æuÒE&ö¦V7E&ö÷BÅ·7G&–æuÒE7FFU&ö÷B¢GF‡2ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuF‡2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷@¢GöÆ–7’ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuöÆ–7’Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷@¢G&W7VÇG2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E¶ö&¦V7EÕÓ£¦æWr‚¢f÷&V6‚‚FFFW"–â‚GöÆ–7’æFFW'2’’°¢F6æF–FFW2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚¢F6æF–FFW2äFB‚„¦ö–âÕF‚GF‡2äFFW'2…·7G&–æuÒFFFW"æ–B²ræ§6öâr’’¢–b…·7G&–æuÒFFFW"æ–BÖWv÷Væ6Æuö6ö×æ–öâr’²F6æF–FFW2äFB‚„¦ö–âÕF‚GF‡2äÖ—76–öäFFW$ö'6W'fF–öç2v÷Væ6ÆrÖ6ö×æ–öâæ§6öâr’’Ð¢Fö'6W'fF–öâÒFçVÆÀ¢Fö'6W'fF–öåF‚Òrp¢f÷&V6‚‚F6æF–FFR–âF6æF–FFW2’°¢–b‚Öæ÷B…FW7BÕF‚ÔÆ—FW&ÅF‚F6æF–FFRÕF…G—RÆVb’’²6öçF–çVRÐ¢G'’°¢GfÇVRÒvWBÔ6öçFVçBÕ&rÔÆ—FW&ÅF‚F6æF–FFRÂ6öçfW'Dg&öÒÔ§6öâÔFFT¶–æB7G&–æp¢–b…·7G&–æuÒGfÇVRæFFW%ö–BÖW·7G&–æuÒFFFW"æ–B’²Fö'6W'fF–öãÒGfÇVS²Fö'6W'fF–öåFƒÒF6æF–FFS²'&V²Ð¢Ò6F6‚²Ð¢Ð¢GfÆ–E&V6V—BÒFfÇ6P¢F–çFVw&—G•fÆ–BÒFfÇ6P¢Fg&W6‚ÒFfÇ6P¢Fö'6W'fVDBÒrp¢Fg&W6…VçF–ÂÒrp¢F6öææV7F–öâÒwVçfW&–f–VBp¢F6Æ–×2Ò‚¢–b‚FçVÆÂÖæRFö'6W'fF–öâ’°¢FÖ—76–ærÒ‚GöÆ–7’æFFW%÷&V6V—Bç&WV—&VEöf–VÆG2Âv†W&RÔö&¦V7B²FçVÆÂÖWFö'6W'fF–öâå4ö&¦V7Bå&÷W'F–W5µ·7G&–æuÒEõÒÖ÷"·7G&–æuÓ£¤—4çVÆÄ÷%v†—FU76R…·7G&–æuÒFö'6W'fF–öââ…·7G&–æuÒEò’’Ò¢GfÆ–E&V6V—BÒFÖ—76–ærä6÷VçBÖWÖæB·7G&–æuÒFö'6W'fF–öâæö'6W'fF–öå÷6†#SbÖÖF6‚uå¶ÖcÓ•×³cGÒBp¢–b‚GfÆ–E&V6V—BÖæB…·7G&–æuÒFö'6W'fF–öâç&V6V—Eö¶–æBÖ6æRvFFW%öö'6W'fF–öârÖ÷"¶&ööÅÒFö'6W'fF–öâæ6öçFVçE÷&VBÖæRFfÇ6RÖ÷"¶&ööÅÒFö'6W'fF–öâæ7&VFVçF–Ç5÷&VBÖæRFfÇ6R’’²GfÆ–E&V6V—BÒFfÇ6RÐ¢–b‚GfÆ–E&V6V—B’°¢Fö'6W'fVDBÒ·7G&–æuÒFö'6W'fF–öâæö'6W'fVEö@¢Fg&W6…VçF–ÂÒ·7G&–æuÒFö'6W'fF–öâæg&W6…÷VçF–À¢Fg&W6‚ÒG'’²´FFUF–ÖTöfg6WEÓ£¥'6R‚Fg&W6…VçF–Â’ÖwB´FFUF–ÖTöfg6WEÓ£¥WF4æ÷rÒ6F6‚²FfÇ6RÐ¢–b‚Fö'6W'fF–öâå4ö&¦V7Bå&÷W'F–W5²v6öææV7F–öå÷7FFRuÒ’²F6öææV7F–öâÒ·7G&–æuÒFö'6W'fF–öâæ6öææV7F–öå÷7FFRÐ¢VÇ6V–b‚Fö'6W'fF–öâå4ö&¦V7Bå&÷W'F–W5²v6öææV7F–öâuÒ’²F6öææV7F–öâÒ·7G&–æuÒFö'6W'fF–öâæ6öææV7F–öâÐ¢VÇ6R²F6öææV7F–öâÒvö'6W'fVEöÖWFFFrÐ¢F6Æ–×2Ò‚Fö'6W'fF–öâæ6Æ–×2Âf÷$V6‚Ôö&¦V7B²·7G&–æuÒEòÒ¢–b‚F6Æ–×2ä6÷VçBÖÇBÖ÷"‚F6Æ–×2Âv†W&RÔö&¦V7B²EòÖæ÷F–â‚FFFW"æÆÆ÷vVEö6Æ–×2’Ò’ä6÷VçBÖwB’²GfÆ–E&V6V—CÒFfÇ6S²F–çFVw&—G•fÆ–CÒFfÇ6RÐ¢–b‚Fö'6W'fF–öâå4ö&¦V7Bå&÷W'F–W5²w&V6V—E÷6†#SbuÒÖæB·7G&–æuÒFö'6W'fF–öâç&V6V—E÷6†#SbÖÖF6‚uå¶ÖcÓ•×³cGÒBr’°¢G'’²F–çFVw&—G•fÆ–BÒ·7G&–æuÒFö'6W'fF–öâç&V6V—E÷6†#SbÖ6W„vWBÔ&¶ó“TÆV&æ–ætö&¦V7D†6‚ÕfÇVR„vWBÔ&¶ó“TFFW%&V6V—D†6„ÖFW&–ÂÕ&V6V—BFö'6W'fF–öâ’’Ò6F6‚²F–çFVw&—G•fÆ–BÒFfÇ6RÐ¢Ð¢Ð¢Ð¢G'VçF–ÖU7FFRÒ–b‚Öæ÷BGfÆ–E&V6V—B’²wVæf–Æ&ÆRrÒVÇ6V–b‚Öæ÷BF–çFVw&—G•fÆ–B’²wVçfW&–f–VEö–çFVw&—G’rÒVÇ6V–b‚Öæ÷BFg&W6‚’²wVæf–Æ&ÆU÷7FÆRrÒVÇ6R²vö'6W'fVEög&W6‚rÐ¢G&W7VÇG2äFB…·67W7FöÖö&¦V7EÔ°¢FFW%ö–BÒ·7G&–æuÒFFFW"æ–@¢F—7Æ•öæÖRÒ·7G&–æuÒFFFW"æF—7Æ•öæÖP¢æF—fUö&÷VæF'’Ò·7G&–æuÒFFFW"ææF—fUö&÷VæF'¢6öæf–wW&VE÷7FFRÒ·7G&–æuÒFFFW"æ6öæf–wW&VE÷7FFP¢'VçF–ÖU÷7FFRÒG'VçF–ÖU7FFP¢6öææV7F–öåö6Æ–ÒÒF6öææV7F–öà¢6Æ–×2ÒF6Æ–×0¢ö'6W'fVEöBÒFö'6W'fVD@¢g&W6…÷VçF–ÂÒFg&W6…VçF–À¢ö'6W'fF–öå÷F‚ÒFö'6W'fF–öåF€¢&V6V—Eö–çFVw&—G•÷fÆ–BÒF–çFVw&—G•fÆ–@¢VffV7BÒw&÷÷6ÅööæÇ’p¢WF†÷&—G’ÒvæöæRp¢Ò¢Ð¢&WGW&âG&W7VÇG2åFô'&’‚§Ð ¦gVæ7F–öâWFFRÔ&¶ó“TÆö6ÄFFW$ö'6W'fF–öç2°¢´6ÖFÆWD&–æF–ær‚•Ð¢&Ò…µ&ÖWFW"„ÖæFF÷'’•Õ·7G&–æuÒE&ö¦V7E&ö÷BÅ·7G&–æuÒE7FFU&ö÷B¢Fæ÷rÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷p¢GVçF–ÂÒFæ÷räFDÖ–çWFW2ƒR¢G&V6V—G2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E¶ö&¦V7EÕÓ£¦æWr‚¢GVæf–Æ&ÆRÒ´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚ ¢gVæ7F–öâvWBÔö'6W'fF–öäF–vW7B°¢&Ò…µ&ÖWFW"„ÖæFF÷'’•ÒEfÇVR¢&WGW&âvWBÔ&¶ó“TÆV&æ–ætö&¦V7D†6‚ÕfÇVREfÇVP¢Ð ¢G'’°¢G&ö6W72ÒvWBÕ&ö6W72ÔæÖRt÷Vä6ÆråG&’åv–åT’rÔW'&÷$7F–öâ7F÷Â6VÆV7BÔö&¦V7BÔf—'7B¢GF‚ÒG&ö6W72äÖ–äÖöGVÆRäf–ÆTæÖP¢G6–væGW&RÒ„vWBÔWF†VçF–6öFU6–væGW&RÔÆ—FW&ÅF‚GF‚’å7FGW0¢FÆ—7FVæW'2Ò„vWBÔæWED56öææV7F–öâÕ7FFRÆ—7FVâÔÆö6Å÷'Bƒsƒ’ÔW'&÷$7F–öâ7F÷Âv†W&RÔö&¦V7B²EòäÆö6ÄFG&W72Ö–â‚s#rãããrÂs££r’Ò¢F6Æ–×2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚“²F6Æ–×2äFB‚w&ö6W75÷'Vææ–ærr¢–b‚G6–væGW&RÖWufÆ–Br’²F6Æ–×2äFB‚w6–væVEö&–æ'’r’Ð¢–b‚FÆ—7FVæW'2ä6÷VçBÖwB’²F6Æ–×2äFB‚vÆö÷&6µövFWv•öÆ—7FVæ–ærr’Ð¢FWf–FVæ6RÒ¶÷&FW&VEÔ²&öGV7CÒt÷Vä6Ær6ö×æ–öâs²fW'6–öãÕ·7G&–æuÒG&ö6W72äÖ–äÖöGVÆRäf–ÆUfW'6–öä–æfòå&öGV7EfW'6–öã²6–væGW&SÕ·7G&–æuÒG6–væGW&S²Æö÷&6µöÆ—7FVæW%ö6÷VçCÒFÆ—7FVæW'2ä6÷VçBÐ¢G&V6V—G2äFB‚…&Vv—7FW"Ô&¶ó“TFFW$ö'6W'fF–öâÕ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BÔFFW$–B÷Væ6Æuö6ö×æ–öâÔFFW%fW'6–öâ…·7G&–æuÒG&ö6W72äÖ–äÖöGVÆRäf–ÆUfW'6–öä–æfòå&öGV7EfW'6–öâ’Ô†÷7D÷%FVæçBFVçc¤4ôÕUDU$äÔRÕ6÷W&6T¶–æB6ö×æ–öåöF–væ÷7F–75öÖWFFFÕ6÷W&6U&VfW&Væ6RvÆö6Â6öçFVçBÖg&VR6–væVB×&ö6W72æBÆö÷&6²ÖÆ—7FVæW"ö'6W'fF–öârÔ6Æ–×2F6Æ–×2åFô'&’‚’Ôö'6W'fVDBFæ÷rÔg&W6…VçF–ÂGVçF–ÂÔö'6W'fF–öå6†#Sb„vWBÔö'6W'fF–öäF–vW7BÕfÇVRFWf–FVæ6R’Ô6öææV7F–öå7FFRB†–b‚FÆ—7FVæW'2ä6÷VçBÖwB—²vö'6W'fVEö6öææV7FVBwÖVÇ6W²vö'6W'fVE÷&W6VçBwÒ’’¢Ð¢6F6‚²GVæf–Æ&ÆRäFB‚v÷Væ6Æuö6ö×æ–öâr’Ð ¢G'’°¢G6¶vRÒvWBÔ…6¶vRÔæÖRtÖ–7&÷6ögBä6÷–Æ÷BrÔW'&÷$7F–öâ7F÷Â6VÆV7BÔö&¦V7BÔf—'7B¢–b‚FçVÆÂÖWG6¶vR’²F‡&÷rw6¶vRÖ—76–ærrÐ¢G&ö6W76W2Ò„vWBÕ&ö6W72ÔæÖRv×66÷–Æ÷BrÔW'&÷$7F–öâ6–ÆVçFÇ”6öçF–çVR¢F6Æ–×2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚“²F6Æ–×2äFB‚w6¶vU÷&W6VçBr¢–b‚G&ö6W76W2ä6÷VçBÖwB’²F6Æ–×2äFB‚w&ö6W75÷'Vææ–ærr’Ð¢G6–væGW&UfÆ–BÒFfÇ6P¢–b‚G&ö6W76W2ä6÷VçBÖwB’²G'’²G6–væGW&UfÆ–BÒ„vWBÔWF†VçF–6öFU6–væGW&RÔÆ—FW&ÅF‚G&ö6W76W5³ÒäÖ–äÖöGVÆRäf–ÆTæÖR’å7FGW2ÖWufÆ–BrÒ6F6‚²ÒÐ¢–b‚G6–væGW&UfÆ–B’²F6Æ–×2äFB‚w6¶vU÷6–væGW&U÷fÆ–Br’Ð¢FWf–FVæ6RÒ¶÷&FW&VEÔ²6¶vSÕ·7G&–æuÒG6¶vRäæÖS²fW'6–öãÕ·7G&–æuÒG6¶vRåfW'6–öã²6–væGW&Uö¶–æCÕ·7G&–æuÒG6¶vRå6–væGW&T¶–æC²&ö6W75ö6÷VçCÒG&ö6W76W2ä6÷VçC²W†V7WF&ÆU÷6–væGW&U÷fÆ–CÒG6–væGW&UfÆ–BÐ¢G&V6V—G2äFB‚…&Vv—7FW"Ô&¶ó“TFFW$ö'6W'fF–öâÕ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BÔFFW$–BÖ–7&÷6ögEö6÷–Æ÷BÔFFW%fW'6–öâ…·7G&–æuÒG6¶vRåfW'6–öâ’Ô†÷7D÷%FVæçBFVçc¤4ôÕUDU$äÔRÕ6÷W&6T¶–æB&ö6W75öæE÷6¶vUöÖWFFFÕ6÷W&6U&VfW&Væ6RvÆö6Â6öçFVçBÖg&VR6¶vRæB&ö6W72ö'6W'fF–öârÔ6Æ–×2F6Æ–×2åFô'&’‚’Ôö'6W'fVDBFæ÷rÔg&W6…VçF–ÂGVçF–ÂÔö'6W'fF–öå6†#Sb„vWBÔö'6W'fF–öäF–vW7BÕfÇVRFWf–FVæ6R’Ô6öææV7F–öå7FFRö'6W'fVE÷&W6VçB’¢Ð¢6F6‚²GVæf–Æ&ÆRäFB‚vÖ–7&÷6ögEö6÷–Æ÷Br’Ð ¢G'’°¢G6¶vRÒvWBÔ…6¶vRÔæÖRt÷Vä’ä6†DuBÔFW6·F÷rÔW'&÷$7F–öâ7F÷Â6VÆV7BÔö&¦V7BÔf—'7B¢–b‚FçVÆÂÖWG6¶vR’²F‡&÷rw6¶vRÖ—76–ærrÐ¢G&ö6W76W2Ò„vWBÕ&ö6W72Âv†W&RÔö&¦V7B²Eòå&ö6W74æÖRÖWt6†DuB6Æ76–2rÒ¢F6Æ–×2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚“²F6Æ–×2äFB‚w6¶vU÷&W6VçBr“²F6Æ–×2äFB‚w6¶vUö–FVçF—G•öö'6W'fVBr¢–b‚G&ö6W76W2ä6÷VçBÖwB’²F6Æ–×2äFB‚w&ö6W75÷'Vææ–ærr’Ð¢FWf–FVæ6RÒ¶÷&FW&VEÔ²6¶vSÕ·7G&–æuÒG6¶vRäæÖS²fW'6–öãÕ·7G&–æuÒG6¶vRåfW'6–öã²6–væGW&Uö¶–æCÕ·7G&–æuÒG6¶vRå6–væGW&T¶–æC²&ö6W75ö6÷VçCÒG&ö6W76W2ä6÷VçBÐ¢G&V6V—G2äFB‚…&Vv—7FW"Ô&¶ó“TFFW$ö'6W'fF–öâÕ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BÔFFW$–B6†FwBÔFFW%fW'6–öâ…·7G&–æuÒG6¶vRåfW'6–öâ’Ô†÷7D÷%FVæçBFVçc¤4ôÕUDU$äÔRÕ6÷W&6T¶–æB&ö6W75öæE÷6¶vUöÖWFFFÕ6÷W&6U&VfW&Væ6RvÆö6Â6öçFVçBÖg&VR6¶vRæB&ö6W72ö'6W'fF–öârÔ6Æ–×2F6Æ–×2åFô'&’‚’Ôö'6W'fVDBFæ÷rÔg&W6…VçF–ÂGVçF–ÂÔö'6W'fF–öå6†#Sb„vWBÔö'6W'fF–öäF–vW7BÕfÇVRFWf–FVæ6R’Ô6öææV7F–öå7FFRö'6W'fVE÷&W6VçB’¢Ð¢6F6‚²GVæf–Æ&ÆRäFB‚v6†FwBr’Ð ¢G'’°¢G6¶vW2Ò„vWBÔ…6¶vRÂv†W&RÔö&¦V7B²EòäæÖRÖ–â‚t÷Vä’ä6öFW‚rÂt÷Vä’ä6öFW„&WFr’Ò¢–b‚G6¶vW2ä6÷VçBÖÇB’²F‡&÷rw6¶vRÖ—76–ærrÐ¢G&ö6W76W2Ò„vWBÕ&ö6W72Âv†W&RÔö&¦V7B²Eòå&ö6W74æÖRÖ–â‚v6öFW‚rÂv6öFW‚Ö6öFRÖÖöFRÖ†÷7BrÂt6†DuB„&WF’r’Ò¢F6Æ–×2Ò´6öÆÆV7F–öç2ävVæW&–2äÆ—7E·7G&–æuÕÓ£¦æWr‚“²F6Æ–×2äFB‚w6¶vU÷&W6VçBr“²F6Æ–×2äFB‚vÖçVÅö†æFöfeööæÇ’r¢–b‚G&ö6W76W2ä6÷VçBÖwB’²F6Æ–×2äFB‚w&ö6W75÷'Vææ–ærr’Ð¢GfÆ–FF–öåF‚Ò¦ö–âÕF‚FVçc¥U4U%$ôd”ÄRræ6öFW…ÇWG5Æ&¶òÓ“UÇfÆ–FF–öâæ§6öâp¢GWEfÆ–BÒFfÇ6P¢–b…FW7BÕF‚ÔÆ—FW&ÅF‚GfÆ–FF–öåF‚ÕF…G—RÆVb’²G'’²GWEfÆ–BÒ¶&ööÅÒ‚„vWBÔ6öçFVçBÕ&rÔÆ—FW&ÅF‚GfÆ–FF–öåF‚Â6öçfW'Dg&öÒÔ§6öâ’æö²’Ò6F6‚²ÒÐ¢–b‚GWEfÆ–B’²F6Æ–×2äFB‚v&¶õ÷WE÷fÆ–FFVBr’Ð¢GfW'6–öç2Ò‚G6¶vW2Âf÷$V6‚Ôö&¦V7B²·7G&–æuÒEòåfW'6–öâÒ¢FWf–FVæ6RÒ¶÷&FW&VEÔ²6¶vW3Ô‚G6¶vW2Âf÷$V6‚Ôö&¦V7B²·7G&–æuÒEòäæÖRÒ“²fW'6–öç3ÒGfW'6–öç3²&ö6W75ö6÷VçCÒG&ö6W76W2ä6÷VçC²&¶õ÷WE÷fÆ–FFVCÒGWEfÆ–C²†æFöfcÒvÖçVÅööæÇ’rÐ¢G&V6V—G2äFB‚…&Vv—7FW"Ô&¶ó“TFFW$ö'6W'fF–öâÕ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BÔFFW$–B6öFW‚ÔFFW%fW'6–öâ‚GfW'6–öç2Ö¦ö–âr²r’Ô†÷7D÷%FVæçBFVçc¤4ôÕUDU$äÔRÕ6÷W&6T¶–æB†÷7Eö6öçFW‡EöÖWFFFÕ6÷W&6U&VfW&Væ6RvÆö6Â6öçFVçBÖg&VR†÷7B6¶vRÂ&ö6W72ÂæBWB×fÆ–FF–öâö'6W'fF–öârÔ6Æ–×2F6Æ–×2åFô'&’‚’Ôö'6W'fVDBFæ÷rÔg&W6…VçF–ÂGVçF–ÂÔö'6W'fF–öå6†#Sb„vWBÔö'6W'fF–öäF–vW7BÕfÇVRFWf–FVæ6R’Ô6öææV7F–öå7FFRö'6W'fVE÷&W6VçB’¢Ð¢6F6‚²GVæf–Æ&ÆRäFB‚v6öFW‚r’Ð ¢&WGW&â·67W7FöÖö&¦V7EÔ°¢ö'6W'fVDBÒFæ÷råFõ7G&–ær‚vòr¢g&W6…VçF–ÂÒGVçF–ÂåFõ7G&–ær‚vòr¢&V6V—D6÷VçBÒG&V6V—G2ä6÷Vç@¢&V6V—G2ÒG&V6V—G2åFô'&’‚¢Væf–Æ&ÆRÒGVæf–Æ&ÆRåFô'&’‚¢6öçFVçE&VBÒFfÇ6P¢7&VFVçF–Ç5&VBÒFfÇ6P¢WF†÷&—G’ÒvæöæRp¢Ð§Ð ¦gVæ7F–öâFW7BÔ&¶ó“TFV6—6–öäÆV&æ–æt6†–â°¢´6ÖFÆWD&–æF–ær‚•Ð¢&Ò…µ&ÖWFW"„ÖæFF÷'’•Õ·7G&–æuÒE&ö¦V7E&ö÷BÅ·7G&–æuÒE7FFU&ö÷B¢G'’°¢GF‡2ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuF‡2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷@¢G&WÆ’ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æu&WÆ’Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕF‡2GF‡0¢&WGW&â·67W7FöÖö&¦V7EÔ²fÆ–CÒG&WÆ’åfÆ–C²W'&÷'3ÒG&WÆ’äW'&÷'3²WfVçD6÷VçCÒG&WÆ’äWfVçD6÷VçC²†VD†6ƒÒG&WÆ’ä†VD†6ƒ²&ö¦V7F–öä—4WF†÷&—G“ÒFfÇ6S²Æ–Ö—FF–öãÒu4„Ó#Sb6†–æ–ærFWFV7G2÷&F–æ'’VF—G2'WB—2æ÷BW‡FW&æÆÇ’æ6†÷&VBv–ç7B6ÖR×W6W"gVÆÂ&Ww&—FR÷"6ÆVâF–ÂG'Væ6F–öâârÐ¢Ð¢6F6‚²&WGW&â·67W7FöÖö&¦V7EÔ²fÆ–CÒFfÇ6S²W'&÷'3Ô‚EòäW†6WF–öâäÖW76vR“²WfVçD6÷VçCÓ²†VD†6ƒÒrs²&ö¦V7F–öä—4WF†÷&—G“ÒFfÇ6S²Æ–Ö—FF–öãÒufW&–f–6F–öâf–ÆVB6Æ÷6VBârÒÐ§Ð ¦gVæ7F–öâvWBÔ&¶ó“TFV6—6–öäÆV&æ–æu7FGW2°¢´6ÖFÆWD&–æF–ær‚•Ð¢&Ò…µ&ÖWFW"„ÖæFF÷'’•Õ·7G&–æuÒE&ö¦V7E&ö÷BÅ·7G&–æuÒE7FFU&ö÷B¢GF‡2ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuF‡2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷@¢GöÆ–7’ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuöÆ–7’Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷@¢G&WÆ’ÒvWBÔ&¶ó“TFV6—6–öäÆV&æ–æu&WÆ’Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕF‡2GF‡0¢F÷VâÒ‚G&WÆ’ä7–6ÆW2Âv†W&RÔö&¦V7B²Eòç7FGW2ÖWv7F—fRrÒ¢F7F—fRÒ–b‚F÷Vâä6÷VçBÖW’²F÷Vå³ÒÒVÇ6R²FçVÆÂÐ¢·67W7FöÖö&¦V7EÔ°¢–æ—F–Æ—¦VBÒFW7BÕF‚ÔÆ—FW&ÅF‚GF‡2äÆVFvW"ÕF…G—RÆV`¢6†–åfÆ–BÒ¶&ööÅÒG&WÆ’åfÆ–@¢6†–äW'&÷'2Ò‚G&WÆ’äW'&÷'2¢WfVçD6÷VçBÒ¶–çEÒG&WÆ’äWfVçD6÷Vç@¢†VD†6‚Ò·7G&–æuÒG&WÆ’ä†VD†6€¢7–6ÆT6÷VçBÒ‚G&WÆ’ä7–6ÆW2’ä6÷Vç@¢÷Vä7–6ÆT6÷VçBÒF÷Vâä6÷Vç@¢7F—fT7–6ÆRÒ–b‚FçVÆÂÖWF7F—fR’²FçVÆÂÒVÇ6R²·67W7FöÖö&¦V7EÒ„6öçfW'EFòÔ&¶ó“TÆV&æ–æu&ö¦V7F–öä7–6ÆRÔ7–6ÆRF7F—fR’Ð¢7–6ÆW2Ò‚G&WÆ’ä7–6ÆW2Âf÷$V6‚Ôö&¦V7B²·67W7FöÖö&¦V7EÒ„6öçfW'EFòÔ&¶ó“TÆV&æ–æu&ö¦V7F–öä7–6ÆRÔ7–6ÆREò’Ò¢FFW'2Ò„vWBÔ&¶ó“TFFW$f'&–57FGW2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷B¢FFW$WF†÷&—G’ÒvæöæRp¢ÖöFRÒw6†F÷uöÆV&æ–ærp¢W‡Æ÷&F–öä6W&6VçBÒ#P¢&÷FV7FVDW†V7WF–öäWf–FVæ6UW&6VçBÒsP¢&ö¦V7F–öä—4WF†÷&—G’ÒFfÇ6P¢&öÖ÷F–öäFVfVÇBÒw&÷÷6VEööæÇ’p¢W†V7WF–öäWF†÷&—G’Òv÷W&F–öç5÷gööæÇ’p¢Ð§Ð ¤W‡÷'BÔÖöGVÆTÖVÖ&W"ÔgVæ7F–öâvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuF‡2ÂvWBÔ&¶ó“TFV6—6–öäÆV&æ–æuöÆ–7’ÂæWrÔ&¶ó“TFV6—6–öä7–6ÆRÂFBÔ&¶ó“TFV6—6–öå&V6÷&BÂ6WBÔ&¶ó“TÆW76öä6æF–FFU&Wf–WrÂ6Æ÷6RÔ&¶ó“TFV6—6–öä7–6ÆRÂ&Vv—7FW"Ô&¶ó“TFFW$ö'6W'fF–öâÂvWBÔ&¶ó“TFFW$f'&–57FGW2ÂWFFRÔ&¶ó“TÆö6ÄFFW$ö'6W'fF–öç2ÂFW7BÔ&¶ó“TFV6—6–öäÆV&æ–æt6†–âÂvWBÔ&¶ó“TFV6—6–öäÆV&æ–æu7FGW0