Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.Operations.psm1') -Force

function Get-Arko95MissionHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-Arko95MissionObjectHash {
    param([Parameter(Mandatory)]$Value)
    return Get-Arko95MissionHash -Text ($Value | ConvertTo-Json -Compress -Depth 32)
}

function ConvertTo-Arko95MissionText {
    param(
        [AllowNull()]$Value,
        [int]$MaximumLength = 500,
        [string]$Fallback = ''
    )
    if ($null -eq $Value) { return $Fallback }
    $clean = (([string]$Value -replace '[\u0000-\u001F\u007F]+',' ') -replace '\s+',' ').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }
    if ($clean.Length -gt $MaximumLength) { return $clean.Substring(0,$MaximumLength) }
    return $clean
}

function Test-Arko95MissionCredentialText {
    param([Parameter(Mandatory)][string]$Text)
    $namedSecret = '(?i)(password|passwd|api[ _-]?key|access[ _-]?token|refresh[ _-]?token|client[ _-]?secret|private[ _-]?key|recovery[ _-]?code)\s*[:=]\s*\S+'
    $longToken = '(?<![A-Za-z0-9])[A-Za-z0-9_\-\/+]{48,}={0,2}(?![A-Za-z0-9])'
    return ($Text -match $namedSecret) -or ($Text -match $longToken)
}

function Get-Arko95MissionControlPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$StateRoot
    )
    $core = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = Join-Path $core.StateDir 'mission-control' }
    $candidate = [System.IO.Path]::GetFullPath($StateRoot)
    $stateRoot = [System.IO.Path]::GetFullPath($core.StateDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if (-not $candidate.StartsWith($stateRoot + [System.IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Mission Control state must remain beneath this project state directory.'
    }
    [pscustomobject]@{
        Root         = $candidate
        Policy       = Join-Path $core.Root 'config\mission-control.json'
        Events       = Join-Path $candidate 'events.jsonl'
        Projection   = Join-Path $candidate 'projection.json'
        Artifacts    = Join-Path $candidate 'artifacts'
        Presentations = Join-Path $candidate 'presentations'
    }
}

function Get-Arko95MissionControlPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $paths = Get-Arko95MissionControlPaths -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $paths.Policy -PathType Leaf)) { throw 'Mission Control policy is missing.' }
    $policy = Get-Content -Raw -LiteralPath $paths.Policy | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String
    if ($policy.schema_version -ne 1 -or $policy.default_effect -ne 'proposal_only' -or $policy.maximum_open_missions -ne 1) {
        throw 'Mission Control policy must remain schema v1, proposal-only by default, and single-open-mission.'
    }
    $expectedStages = @('intake','decompose','route_delegate','execute','verify','persist_learn','notify_present')
    $actualStages = @($policy.stages | ForEach-Object { [string]$_.id })
    if (($actualStages -join '|') -cne ($expectedStages -join '|')) { throw 'Mission Control stage order changed or is incomplete.' }
    $opsPolicy = Get-Arko95OperationsPolicy -ProjectRoot $ProjectRoot
    $compiled = @($opsPolicy.automatic_capabilities | ForEach-Object { [string]$_.id } | Sort-Object)
    if ($compiled.Count -lt 1) { throw 'Mission Control requires at least one compiled Operations VP capability.' }
    $policy | Add-Member -NotePropertyName 'allowed_operations_capabilities' -NotePropertyValue @($compiled) -Force
    return $policy
}

function Enter-Arko95MissionMutex {
    param([Parameter(Mandatory)][string]$StateRoot)
    $digest = Get-Arko95MissionHash -Text ([System.IO.Path]::GetFullPath($StateRoot).ToLowerInvariant())
    $mutex = [Threading.Mutex]::new($false,('Local\ARKO95-MissionControl-' + $digest.Substring(0,20)))
    try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10)) }
    catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { $mutex.Dispose(); throw 'Mission Control is busy in another process.' }
    return $mutex
}

function Exit-Arko95MissionMutex {
    param([AllowNull()]$Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

function Initialize-Arko95MissionControlState {
    param([Parameter(Mandatory)]$Paths)
    foreach ($directory in @($Paths.Root,$Paths.Artifacts,$Paths.Presentations)) {
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $item = Get-Item -LiteralPath $directory -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Mission Control refuses reparse-point state directories.' }
    }
    if (-not (Test-Path -LiteralPath $Paths.Events -PathType Leaf)) {
        [System.IO.File]::WriteAllText($Paths.Events,'',[System.Text.UTF8Encoding]::new($false))
    }
}

function Get-Arko95MissionEventHashMaterial {
    param([Parameter(Mandatory)]$Event)
    [ordered]@{
        schema_version   = [int]$Event.schema_version
        sequence         = [int]$Event.sequence
        event_id         = [string]$Event.event_id
        mission_id       = [string]$Event.mission_id
        timestamp        = [string]$Event.timestamp
        event_type       = [string]$Event.event_type
        from_stage       = [string]$Event.from_stage
        to_stage         = [string]$Event.to_stage
        actor_id         = [string]$Event.actor_id
        actor_role       = [string]$Event.actor_role
        objective_sha256 = [string]$Event.objective_sha256
        policy_sha256    = [string]$Event.policy_sha256
        expected_version = [int]$Event.expected_version
        new_version      = [int]$Event.new_version
        status           = [string]$Event.status
        payload          = $Event.payload
        linked_receipts  = @($Event.linked_receipts)
        previous_hash    = [string]$Event.previous_hash
    }
}

function Read-Arko95MissionEvents {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt 8388608) { throw 'Mission Control event log exceeds its v1 size limit.' }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Mission Control refuses an event log reparse point.' }
    $events = [Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 131072) { throw 'Mission Control event exceeds its v1 size limit.' }
        $events.Add(($line | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String))
    }
    return $events.ToArray()
}

function Get-Arko95MissionReplay {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Paths
    )
    $policy = Get-Arko95MissionControlPolicy -ProjectRoot $ProjectRoot
    $policyHash = Get-Arko95MissionObjectHash -Value $policy
    $stages = @($policy.stages | ForEach-Object { [string]$_.id })
    $events = @(Read-Arko95MissionEvents -Path $Paths.Events)
    $missions = @{}
    $errors = [Collections.Generic.List[string]]::new()
    $previousHash = ('0' * 64)
    $expectedSequence = 1

    foreach ($event in $events) {
        try {
            if ($event.schema_version -ne 1) { throw 'unsupported event schema' }
            if ([int]$event.sequence -ne $expectedSequence) { throw 'non-contiguous sequence' }
            if ([string]$event.previous_hash -cne $previousHash) { throw 'previous hash mismatch' }
            if ([string]$event.policy_sha256 -cne $policyHash) { throw 'policy digest mismatch' }
            $computed = Get-Arko95MissionObjectHash -Value (Get-Arko95MissionEventHashMaterial -Event $event)
            if ([string]$event.event_hash -cne $computed) { throw 'event hash mismatch' }
            $id = [string]$event.mission_id
            if ($event.event_type -eq 'mission_created') {
                if ($missions.ContainsKey($id)) { throw 'duplicate mission creation' }
                $openCount = @($missions.Values | Where-Object { $_.status -notin @('complete','aborted') }).Count
                if ($openCount -ge [int]$policy.maximum_open_missions) { throw 'single-open-mission invariant violated' }
                if ($event.from_stage -ne '' -or $event.to_stage -ne 'intake' -or $event.expected_version -ne 0 -or $event.new_version -ne 1) { throw 'invalid mission creation transition' }
                if ($event.objective_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'invalid objective digest' }
                $payloadObjective = [string]$event.payload.objective
                if ((Get-Arko95MissionHash -Text $payloadObjective) -cne [string]$event.objective_sha256) { throw 'objective digest mismatch' }
                $missions[$id] = [pscustomobject]@{
                    mission_id = $id; objective = $payloadObjective; objective_sha256 = [string]$event.objective_sha256
                    mode = [string]$event.payload.mode; success_criteria = @($event.payload.success_criteria); constraints = @($event.payload.constraints)
                    stage = 'intake'; status = [string]$event.status; version = 1; event_count = 1
                    created_at = [string]$event.timestamp; updated_at = [string]$event.timestamp; last_event_hash = [string]$event.event_hash
                    delegation_id = ''; delegation_receipt = ''; duty_id = ''; duty_request_hash = ''; executor_actor_id = ''
                    verification_result = 'unknown'; presentation_path = ''; last_payload = $event.payload
                }
            }
            else {
                if (-not $missions.ContainsKey($id)) { throw 'event references an unknown mission' }
                $mission = $missions[$id]
                if ([string]$event.objective_sha256 -cne [string]$mission.objective_sha256) { throw 'objective drift detected' }
                if ([int]$event.expected_version -ne [int]$mission.version -or [int]$event.new_version -ne ([int]$mission.version + 1)) { throw 'mission version mismatch' }
                if ([string]$event.from_stage -cne [string]$mission.stage) { throw 'event from-stage mismatch' }

                switch ([string]$event.event_type) {
                    'stage_transition' {
                        $fromIndex = [Array]::IndexOf($stages,[string]$mission.stage)
                        $toIndex = [Array]::IndexOf($stages,[string]$event.to_stage)
                        if ($toIndex -ne ($fromIndex + 1)) { throw 'stage skip or backward transition' }
                        if ($mission.status -ne 'active') { throw 'held or terminal mission advanced' }
                        $mission.stage = [string]$event.to_stage
                        $mission.status = [string]$event.status
                    }
                    'mission_held' {
                        if ($event.to_stage -ne $mission.stage) { throw 'hold changed the mission stage' }
                        $mission.status = 'held'
                    }
                    'mission_resumed' {
                        if ($event.to_stage -ne $mission.stage -or $mission.status -ne 'held') { throw 'invalid resume' }
                        $mission.status = 'active'
                    }
                    'mission_aborted' {
                        if ($event.to_stage -ne $mission.stage) { throw 'abort changed the mission stage' }
                        $mission.status = 'aborted'
                    }
                    default { throw 'unsupported event type' }
                }
                $mission.version = [int]$event.new_version
                $mission.event_count = [int]$mission.event_count + 1
                $mission.updated_at = [string]$event.timestamp
                $mission.last_event_hash = [string]$event.event_hash
                $mission.last_payload = $event.payload
                if ($event.to_stage -eq 'route_delegate') {
                    $mission.delegation_id = [string]$event.payload.delegation_id
                    $mission.delegation_receipt = [string]$event.payload.delegation_receipt
                }
                if ($event.to_stage -eq 'execute') {
                    $mission.duty_id = [string]$event.payload.duty_id
                    $mission.duty_request_hash = [string]$event.payload.request_hash
                    $mission.executor_actor_id = [string]$event.actor_id
                }
                if ($event.to_stage -eq 'persist_learn') { $mission.verification_result = [string]$event.payload.verification_result }
                if ($event.to_stage -eq 'notify_present') {
                    $mission.presentation_path = [string]$event.payload.presentation_path
                    $mission.status = 'complete'
                }
            }
            $previousHash = [string]$event.event_hash
            $expectedSequence++
        }
        catch {
            $errors.Add(('event {0}: {1}' -f $expectedSequence,$_.Exception.Message))
            break
        }
    }

    [pscustomobject]@{
        Valid        = $errors.Count -eq 0
        Errors       = $errors.ToArray()
        Events       = $events
        EventCount   = $events.Count
        HeadHash     = $previousHash
        PolicyHash   = $policyHash
        Missions     = @($missions.Values | Sort-Object created_at)
    }
}

function Write-Arko95MissionProjection {
    param([Parameter(Mandatory)]$Paths,[Parameter(Mandatory)]$Replay)
    $projection = [ordered]@{
        schema_version = 1
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        derived_from_event_replay = $true
        chain_valid = [bool]$Replay.Valid
        event_count = [int]$Replay.EventCount
        head_hash = [string]$Replay.HeadHash
        missions = @($Replay.Missions)
    }
    $temp = $Paths.Projection + '.tmp-' + [guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($temp,($projection | ConvertTo-Json -Compress -Depth 24),[System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temp,$Paths.Projection,$true)
}

function Add-Arko95MissionEventUnlocked {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][string]$MissionId,
        [Paramã®4¶‰žËkºwµçyÙ•ÉÍ¥½¸€µ¹”€‘áÁ•Ñ•‘Y•ÉÍ¥½¸¤ìÑ¡É½Ü€5¥ÍÍ¥½¸Ù•ÉÍ¥½¸¥ÌÍÑ…±”ìÉ•™É•Í ‰•™½É”Íå¹¡É½¹¥é¥¹œ¸œô(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹ÍÑ…”€µ¹”€•á•ÕÑ”œ€µ½È€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¹”€…Ñ¥Ù”œ¤ìÑ¡É½Ü€á•ÕÑ¥½¸Íå¹¡É½¹¥é…Ñ¥½¸É•ÅÕ¥É•Ì…¸…Ñ¥Ù”á•ÕÑ”ÍÑ…”¸œô(€€€€€€€€‘½ÁÍA…Ñ¡Ì€ô•ÐµÉ­¼äÕ=Á•É…Ñ¥½¹ÍA…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘=Á•É…Ñ¥½¹ÍMÑ…Ñ•I½½Ð(€€€€€€€€‘‘ÕÑä€ô€‘¹Õ±°(€€€€€€€€‘‘ÕÑåA…Ñ €ô€œœ(€€€€€€€™½É•… € ‘‘¥É•Ñ½Éä¥¸  ‘½ÁÍA…Ñ¡Ì¹A•¹‘¥¹œ°‘½ÁÍA…Ñ¡Ì¹]½É­¥¹œ°‘½ÁÍA…Ñ¡Ì¹½µÁ±•Ñ•°‘½ÁÍA…Ñ¡Ì¹…¥±•°‘½ÁÍA…Ñ¡Ì¹!•±¤¤ì(€€€€€€€€€€€¥˜€ µ¹½Ð€¡Q•ÍÐµA…Ñ €µ1¥Ñ•É…±A…Ñ €‘‘¥É•Ñ½Éä¤¤ì½¹Ñ¥¹Õ”ô(€€€€€€€€€€€™½É•… € ‘…¹‘¥‘…Ñ”¥¸•Ðµ¡¥±‘%Ñ•´€µ1¥Ñ•É…±A…Ñ €‘‘¥É•Ñ½Éä€µ¥±”€µ¥±Ñ•È€‘ÕÑä´¨¹©Í½¸œ€µÉÉ½ÉÑ¥½¸M¥±•¹Ñ±å½¹Ñ¥¹Õ”¤ì(€€€€€€€€€€€€€€€€‘Ù…±Õ”€ô•Ðµ½¹Ñ•¹Ð€µI…Ü€µ1¥Ñ•É…±A…Ñ €‘…¹‘¥‘…Ñ”¹Õ±±9…µ”ð5¥É½Í½™Ð¹A½Ý•ÉM¡•±°¹UÑ¥±¥Ñåq½¹Ù•ÉÑÉ½´µ)Í½¸€µ…Ñ•-¥¹MÑÉ¥¹œ(€€€€€€€€€€€€€€€¥˜€¡mÍÑÉ¥¹t‘Ù…±Õ”¹‘ÕÑå}¥€µ•ÄmÍÑÉ¥¹t‘µ¥ÍÍ¥½¸¹‘ÕÑå}¥¤ì€‘‘ÕÑä€ô€‘Ù…±Õ”ì€‘‘ÕÑåA…Ñ €ô€‘…¹‘¥‘…Ñ”¹Õ±±9…µ”ì‰É•…¬ô(€€€€€€€€€€€ô(€€€€€€€€€€€¥˜€ ‘¹Õ±°€µ¹”€‘‘ÕÑä¤ì‰É•…¬ô(€€€€€€€ô(€€€€€€€¥˜€ ‘¹Õ±°€µ•Ä€‘‘ÕÑä¤ìÑ¡É½Ü€Q¡”±¥¹­•=Á•É…Ñ¥½¹ÌY@‘ÕÑä½Õ±¹½Ð‰”™½Õ¹¸œô(€€€€€€€€‘½µÁ±•Ñ•‘¥É•Ñ½Éä€ômMåÍÑ•´¹%<¹A…Ñ¡tèé•ÑÕ±±A…Ñ  ‘½ÁÍA…Ñ¡Ì¹½µÁ±•Ñ•¤¹QÉ¥µ¹¡mMåÍÑ•´¹%<¹A…Ñ¡tèé¥É•Ñ½ÉåM•Á…É…Ñ½É¡…È¤(€€€€€€€€‘…ÑÕ…±¥É•Ñ½Éä€ômMåÍÑ•´¹%<¹A…Ñ¡tèé•ÑÕ±±A…Ñ  ¡MÁ±¥ÐµA…Ñ €µA…É•¹Ð€‘‘ÕÑåA…Ñ ¤¤¹QÉ¥µ¹¡mMåÍÑ•´¹%<¹A…Ñ¡tèé¥É•Ñ½ÉåM•Á…É…Ñ½É¡…È¤(€€€€€€€¥˜€ ‘…ÑÕ…±¥É•Ñ½Éä€µ¹”€‘½µÁ±•Ñ•‘¥É•Ñ½Éä€µ½È€‘‘ÕÑä¹ÍÑ…ÑÕÌ€µ¹½Ñ¥¸  ½µÁ±•Ñ•œ°Ù•É¥™¥•œ¤¤ìÑ¡É½Ü€‰Q¡”±¥¹­•‘ÕÑä¥Ì€œ ‘‘ÕÑä¹ÍÑ…ÑÕÌ¤œ°¹½Ð¥¸Ñ¡”Ù•É¥™¥•½µÁ±•Ñ•ÅÕ•Õ”¸ˆô(€€€€€€€¥˜€¡mÍÑÉ¥¹t‘‘ÕÑä¹É•ÅÕ•ÍÑ}¡…Í €µ¹”mÍÑÉ¥¹t‘µ¥ÍÍ¥½¸¹‘ÕÑå}É•ÅÕ•ÍÑ}¡…Í ¤ìÑ¡É½Ü€Q¡”‘ÕÑäÉ•ÅÕ•ÍÐ¡…Í ‘½•Ì¹½Ðµ…Ñ Ñ¡”µ¥ÍÍ¥½¸•á•ÕÑ¥½¸•Ù•¹Ð¸œô(€€€€€€€¥˜€¡mÍÑÉ¥¹t‘‘ÕÑä¹É•Ù¥•Ý}¡…Í €µ¹½Ñµ…Ñ €ym„µ˜À´åuìØÑôœ¤ìÑ¡É½Ü€Q¡”½µÁ±•Ñ•‘ÕÑä¥Ìµ¥ÍÍ¥¹œ¥ÑÌ¥¹‘•Á•¹‘•¹ÐÉ•Ù¥•ÜÉ••¥ÁÐ¸œô(€€€€€€€€‘‘ÕÑå¥±•!…Í €ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹!…Í €µQ•áÐ€¡mMåÍÑ•´¹%<¹¥±•tèéI•…‘±±Q•áÐ ‘‘ÕÑåA…Ñ ¤¤(€€€€€€€€‘Á…å±½…€ôm½É‘•É•‘uì(€€€€€€€€€€€‘ÕÑå}¥€ômÍÑÉ¥¹t‘‘ÕÑä¹‘ÕÑå}¥(€€€€€€€€€€€…Á…‰¥±¥Ñä€ômÍÑÉ¥¹t‘‘ÕÑä¹…Á…‰¥±¥Ñä(€€€€€€€€€€€É•ÅÕ•ÍÑ}¡…Í €ômÍÑÉ¥¹t‘‘ÕÑä¹É•ÅÕ•ÍÑ}¡…Í (€€€€€€€€€€€É•Ù¥•Ý}¡…Í €ômÍÑÉ¥¹t‘‘ÕÑä¹É•Ù¥•Ý}¡…Í (€€€€€€€€€€€‘ÕÑå}™¥±•}Í¡„ÈÔØ€ô€‘‘ÕÑå¥±•!…Í (€€€€€€€€€€€•á•ÕÑ¥½¹}½µÁ±•Ñ•€ô€‘ÑÉÕ”(€€€€€€€€€€€µ¥ÍÍ¥½¹}ÍÕ•ÍÍ}¹½Ñ}å•Ñ}Ù•É¥™¥•€ô€‘ÑÉÕ”(€€€€€€€ô(€€€€€€€€‘•Ù•¹Ð€ô‘µÉ­¼äÕ5¥ÍÍ¥½¹MÑ…•QÉ…¹Í¥Ñ¥½¹U¹±½­•€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì€µ5¥ÍÍ¥½¸€‘µ¥ÍÍ¥½¸€µQ½MÑ…”€Ù•É¥™äœ€µÑ½É%€µ¥ÍÍ¥½¸µ•á•ÕÑ¥½¸µ±¥¹­•Èœ€µÑ½ÉI½±”€É••¥ÁÑ}±¥¹­•Èœ€µA…å±½…€‘Á…å±½…€µ1¥¹­•‘I••¥ÁÑÌ ¡mÍÑÉ¥¹t‘‘ÕÑä¹É•ÅÕ•ÍÑ}¡…Í ±mÍÑÉ¥¹t‘‘ÕÑä¹É•Ù¥•Ý}¡…Í °‘‘ÕÑå¥±•!…Í ¤(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì5¥ÍÍ¥½¹%ô‘5¥ÍÍ¥½¹%ìMÑ…”ôÙ•É¥™äœìY•ÉÍ¥½¸ô‘•Ù•¹Ð¹¹•Ý}Ù•ÉÍ¥½¸ìÕÑå%ô‘‘ÕÑä¹‘ÕÑå}¥ìI•Ù¥•ÝI••¥ÁÐô‘‘ÕÑä¹É•Ù¥•Ý}¡…Í ô(€€€ô(€€€™¥¹…±±äìá¥ÐµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µ5ÕÑ•à€‘µÕÑ•àô)ô()™Õ¹Ñ¥½¸½¹™¥É´µÉ­¼äÕ5¥ÍÍ¥½¹Y•É¥™¥…Ñ¥½¸ì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´ (€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘5¥ÍÍ¥½¹%°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥um¥¹Ñt‘áÁ•Ñ•‘Y•ÉÍ¥½¸°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘Y•É¥™¥•É%°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥um½‰©•Ñmut‘¡•­Ì°(€€€€€€€mY…±¥‘…Ñ•M•Ð Á…ÍÌœ°™…¥°œ°‰±½­•œ°Õ¹­¹½Ý¸œ¥umÍÑÉ¥¹t‘I•ÍÕ±Ð€ô€Õ¹­¹½Ý¸œ°(€€€€€€€mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð(€€€€¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘µÕÑ•à€ô€‘¹Õ±°(€€€ÑÉäì(€€€€€€€€‘µÕÑ•à€ô¹Ñ•ÈµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µMÑ…Ñ•I½½Ð€‘Á…Ñ¡Ì¹I½½Ð(€€€€€€€%¹¥Ñ¥…±¥é”µÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±MÑ…Ñ”€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€¥˜€ µ¹½Ð€‘É•Á±…ä¹Y…±¥¤ìÑ¡É½Ü€ 5¥ÍÍ¥½¸•Ù•¹Ð¡…¥¸¥Ì¥¹Ù…±¥è€œ€¬€ ‘É•Á±…ä¹ÉÉ½ÉÌ€µ©½¥¸€œì€œ¤¤ô(€€€€€€€€‘µ¥ÍÍ¥½¸€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹	å%€µI•Á±…ä€‘É•Á±…ä€µ5¥ÍÍ¥½¹%€‘5¥ÍÍ¥½¹%(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹Ù•ÉÍ¥½¸€µ¹”€‘áÁ•Ñ•‘Y•ÉÍ¥½¸¤ìÑ¡É½Ü€5¥ÍÍ¥½¸Ù•ÉÍ¥½¸¥ÌÍÑ…±”ìÉ•™É•Í ‰•™½É”Ù•É¥™¥…Ñ¥½¸¸œô(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹ÍÑ…”€µ¹”€Ù•É¥™äœ€µ½È€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¹”€…Ñ¥Ù”œ¤ìÑ¡É½Ü€Y•É¥™¥…Ñ¥½¸µ…ä‰”É•½É‘•½¹±ä…ÐÑ¡”Y•É¥™äÍÑ…”¸œô(€€€€€€€€‘±•…¹Y•É¥™¥•È€ô½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘Y•É¥™¥•É%€µ5…á¥µÕµ1•¹Ñ €àÀ(€€€€€€€¥˜€¡mÍÑÉ¥¹tèé%Í9Õ±±=É]¡¥Ñ•MÁ…” ‘±•…¹Y•É¥™¥•È¤€µ½È€‘±•…¹Y•É¥™¥•È€µ¥¸  ‘µ¥ÍÍ¥½¸¹•á•ÕÑ½É}…Ñ½É}¥°½Á•É…Ñ¥½¹ÌµÙÀµ‰É½­•Èœ°½Á•¹±…Ý}½µÁ…¹¥½¸œ¤¤ìÑ¡É½Ü€Y•É¥™¥…Ñ¥½¸µÕÍÐ‰”¥¹‘•Á•¹‘•¹Ð™É½´Ñ¡”•á•ÕÑ½È…¹=Á•¹±…Ü…‘…ÁÑ•È¸œô(€€€€€€€€‘¹½Éµ…±¥é•‘¡•­Ì€ôm½±±•Ñ¥½¹Ì¹•¹•É¥Œ¹1¥ÍÑm½‰©•Ñutèé¹•Ü ¤(€€€€€€€™½É•… € ‘¡•¬¥¸  ‘¡•­Ì¤¤ì(€€€€€€€€€€€€‘É¥Ñ•É¥½¸€ô½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘¡•¬¹É¥Ñ•É¥½¸€µ5…á¥µÕµ1•¹Ñ €ÈÐÀ(€€€€€€€€€€€€‘ÍÑ…ÑÕÌ€ô½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘¡•¬¹ÍÑ…ÑÕÌ€µ5…á¥µÕµ1•¹Ñ €ÄØ(€€€€€€€€€€€€‘•Ù¥‘•¹”€ô  ‘¡•¬¹•Ù¥‘•¹•}Í¡„ÈÔØ¤(€€€€€€€€€€€¥˜€¡mÍÑÉ¥¹tèé%Í9Õ±±=É]¡¥Ñ•MÁ…” ‘É¥Ñ•É¥½¸¤€µ½È€‘ÍÑ…ÑÕÌ€µ¹½Ñ¥¸  Á…ÍÌœ°™…¥°œ°‰±½­•œ°Õ¹­¹½Ý¸œ¤¤ìÑ¡É½Ü€Ù•ÉäÙ•É¥™¥…Ñ¥½¸¡•¬É•ÅÕ¥É•Ì„É¥Ñ•É¥½¸…¹„ÑåÁ•ÍÑ…ÑÕÌ¸œô(€€€€€€€€€€€™½É•… € ‘¡…Í ¥¸€‘•Ù¥‘•¹”¤ì¥˜€¡mÍÑÉ¥¹t‘¡…Í €µ¹½Ñµ…Ñ €ym„µ˜À´åuìØÑôœ¤ìÑ¡É½Ü€Y•É¥™¥…Ñ¥½¸•Ù¥‘•¹”µÕÍÐ‰”±¥¹­•‰äM!´ÈÔØ¸œôô(€€€€€€€€€€€¥˜€ ‘ÍÑ…ÑÕÌ€µ•Ä€Á…ÍÌœ€µ…¹€‘•Ù¥‘•¹”¹½Õ¹Ð€µ±Ð€Ä¤ìÑ¡É½Ü€Á…ÍÍ¥¹œÙ•É¥™¥…Ñ¥½¸¡•¬É•ÅÕ¥É•Ì•Ù¥‘•¹”¸œô(€€€€€€€€€€€€‘¹½Éµ…±¥é•‘¡•­Ì¹‘¡m½É‘•É•‘uìÉ¥Ñ•É¥½¸ô‘É¥Ñ•É¥½¸ìÍÑ…ÑÕÌô‘ÍÑ…ÑÕÌì•Ù¥‘•¹•}Í¡„ÈÔØô‘•Ù¥‘•¹”ô¤(€€€€€€€ô(€€€€€€€¥˜€ ‘¹½Éµ…±¥é•‘¡•­Ì¹½Õ¹Ð€µ¹”  ‘µ¥ÍÍ¥½¸¹ÍÕ•ÍÍ}É¥Ñ•É¥„¤¹½Õ¹Ð¤ìÑ¡É½Ü€Y•É¥™¥…Ñ¥½¸µÕÍÐ…‘‘É•ÍÌ•Ù•Éäµ¥ÍÍ¥½¸ÍÕ•ÍÌÉ¥Ñ•É¥½¸•á…Ñ±ä½¹”¸œô(€€€€€€€¥˜€ ‘I•ÍÕ±Ð€µ•Ä€Á…ÍÌœ€µ…¹  ‘¹½Éµ…±¥é•‘¡•­Ìð]¡•É”µ=‰©•Ðì€‘|¹ÍÑ…ÑÕÌ€µ¹”€Á…ÍÌœô¤¹½Õ¹Ð€µÐ€À¤ìÑ¡É½Ü€Q¡”µ¥ÍÍ¥½¸…¹¹½ÐÁ…ÍÌÝ¡¥±”…¹äÉ¥Ñ•É¥½¸¥Ì¹½ÐÁ…ÍÍ•¸œô(€€€€€€€¥˜€ ‘I•ÍÕ±Ð€µ¹”€Á…ÍÌœ¤ìÑ¡É½Ü€™…¥±•°‰±½­•°½ÈÕ¹­¹½Ý¸µ¥ÍÍ¥½¸É•µ…¥¹Ì…ÐY•É¥™ä™½È½Ý¹•Èµ‘¥É•Ñ•É•Ý½É¬½È…‰½ÉÐ¸œô(€€€€€€€€‘Ù•É¥™¥…Ñ¥½¸€ôm½É‘•É•‘uìµ¥ÍÍ¥½¹}¥ô‘5¥ÍÍ¥½¹%ì½‰©•Ñ¥Ù•}Í¡„ÈÔØô‘µ¥ÍÍ¥½¸¹½‰©•Ñ¥Ù•}Í¡„ÈÔØìÙ•É¥™¥•É}¥ô‘±•…¹Y•É¥™¥•ÈìÉ•ÍÕ±Ðô‘I•ÍÕ±Ðì¡•­Ìô‘¹½Éµ…±¥é•‘¡•­Ì¹Q½ÉÉ…ä ¤ô(€€€€€€€€‘É••¥ÁÐ€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹=‰©•Ñ!…Í €µY…±Õ”€‘Ù•É¥™¥…Ñ¥½¸(€€€€€€€€‘Á…å±½…€ôm½É‘•É•‘uìÙ•É¥™¥…Ñ¥½¹}É•ÍÕ±Ðô‘I•ÍÕ±ÐìÙ•É¥™¥•É}¥ô‘±•…¹Y•É¥™¥•ÈìÙ•É¥™¥…Ñ¥½¹}É••¥ÁÐô‘É••¥ÁÐì¡•­Ìô‘¹½Éµ…±¥é•‘¡•­Ì¹Q½ÉÉ…ä ¤ì±•…É¹¥¹}ÁÉ½µ½Ñ¥½¸ôÁÉ½Á½Í•‘}½¹±äœô(€€€€€€€€‘•Ù•¹Ð€ô‘µÉ­¼äÕ5¥ÍÍ¥½¹MÑ…•QÉ…¹Í¥Ñ¥½¹U¹±½­•€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì€µ5¥ÍÍ¥½¸€‘µ¥ÍÍ¥½¸€µQ½MÑ…”€Á•ÉÍ¥ÍÑ}±•…É¸œ€µÑ½É%€‘±•…¹Y•É¥™¥•È€µÑ½ÉI½±”€ÁÉ½½™}Ù•É¥™¥•Èœ€µA…å±½…€‘Á…å±½…€µ1¥¹­•‘I••¥ÁÑÌ  ‘É••¥ÁÐ¤(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì5¥ÍÍ¥½¹%ô‘5¥ÍÍ¥½¹%ìMÑ…”ôÁ•ÉÍ¥ÍÑ}±•…É¸œìY•ÉÍ¥½¸ô‘•Ù•¹Ð¹¹•Ý}Ù•ÉÍ¥½¸ìI•ÍÕ±Ðô‘I•ÍÕ±ÐìY•É¥™¥…Ñ¥½¹I••¥ÁÐô‘É••¥ÁÐô(€€€ô(€€€™¥¹…±±äìá¥ÐµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µ5ÕÑ•à€‘µÕÑ•àô)ô()™Õ¹Ñ¥½¸½µÁ±•Ñ”µÉ­¼äÕ5¥ÍÍ¥½¸ì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´ (€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘5¥ÍÍ¥½¹%°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥um¥¹Ñt‘áÁ•Ñ•‘Y•ÉÍ¥½¸°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘=ÕÑ½µ”°(€€€€€€€mÍÑÉ¥¹mut‘U¹É•Í½±Ù•€ô  ¤°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘9•áÑ=Ý¹•É•¥Í¥½¸°(€€€€€€€mÍÑÉ¥¹t‘=Ý¹•É%€ô€±½…±}½Ý¹•Èœ°(€€€€€€€mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð(€€€€¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘µÕÑ•à€ô€‘¹Õ±°(€€€ÑÉäì(€€€€€€€€‘µÕÑ•à€ô¹Ñ•ÈµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µMÑ…Ñ•I½½Ð€‘Á…Ñ¡Ì¹I½½Ð(€€€€€€€%¹¥Ñ¥…±¥é”µÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±MÑ…Ñ”€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€¥˜€ µ¹½Ð€‘É•Á±…ä¹Y…±¥¤ìÑ¡É½Ü€ 5¥ÍÍ¥½¸•Ù•¹Ð¡…¥¸¥Ì¥¹Ù…±¥è€œ€¬€ ‘É•Á±…ä¹ÉÉ½ÉÌ€µ©½¥¸€œì€œ¤¤ô(€€€€€€€€‘µ¥ÍÍ¥½¸€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹	å%€µI•Á±…ä€‘É•Á±…ä€µ5¥ÍÍ¥½¹%€‘5¥ÍÍ¥½¹%(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹Ù•ÉÍ¥½¸€µ¹”€‘áÁ•Ñ•‘Y•ÉÍ¥½¸¤ìÑ¡É½Ü€5¥ÍÍ¥½¸Ù•ÉÍ¥½¸¥ÌÍÑ…±”ìÉ•™É•Í ‰•™½É”½µÁ±•Ñ¥½¸¸œô(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹ÍÑ…”€µ¹”€Á•ÉÍ¥ÍÑ}±•…É¸œ€µ½È€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¹”€…Ñ¥Ù”œ€µ½È€‘µ¥ÍÍ¥½¸¹Ù•É¥™¥…Ñ¥½¹}É•ÍÕ±Ð€µ¹”€Á…ÍÌœ¤ìÑ¡É½Ü€=¹±ä…¸¥¹‘•Á•¹‘•¹Ñ±äÁ…ÍÍ•µ¥ÍÍ¥½¸µ…ä•¹Ñ•È9½Ñ¥™ä€˜AÉ•Í•¹Ð¸œô(€€€€€€€€‘±•…¹=ÕÑ½µ”€ô½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘=ÕÑ½µ”€µ5…á¥µÕµ1•¹Ñ €ÄÀÀÀ(€€€€€€€€‘±•…¹9•áÐ€ô½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘9•áÑ=Ý¹•É•¥Í¥½¸€µ5…á¥µÕµ1•¹Ñ €ÔÀÀ(€€€€€€€¥˜€¡mÍÑÉ¥¹tèé%Í9Õ±±=É]¡¥Ñ•MÁ…” ‘±•…¹=ÕÑ½µ”¤€µ½ÈmÍÑÉ¥¹tèé%Í9Õ±±=É]¡¥Ñ•MÁ…” ‘±•…¹9•áÐ¤¤ìÑ¡É½Ü€=ÕÑ½µ”…¹¹•áÐ½Ý¹•È‘•¥Í¥½¸…É”É•ÅÕ¥É•¸œô(€€€€€€€€‘±•…¹U¹É•Í½±Ù•€ô  ‘U¹É•Í½±Ù•ð½É… µ=‰©•Ðì½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘|€µ5…á¥µÕµ1•¹Ñ €ÌÀÀôð]¡•É”µ=‰©•Ðì€‘|ô¤(€€€€€€€€‘ÁÉ•Í•¹Ñ…Ñ¥½¸€ôm½É‘•É•‘uì(€€€€€€€€€€€Í¡•µ…}Ù•ÉÍ¥½¸€ô€Äìµ¥ÍÍ¥½¹}¥ô‘5¥ÍÍ¥½¹%ì½‰©•Ñ¥Ù•}Í¡„ÈÔØô‘µ¥ÍÍ¥½¸¹½‰©•Ñ¥Ù•}Í¡„ÈÔØ(€€€€€€€€€€€É•…Ñ•‘}…Ðõm…Ñ•Q¥µ•=™™Í•ÑtèéUÑ9½Ü¹Q½MÑÉ¥¹œ ¼œ¤ì½ÕÑ½µ”ô‘±•…¹=ÕÑ½µ”ìÕ¹É•Í½±Ù•ô‘±•…¹U¹É•Í½±Ù•(€€€€€€€€€€€¹•áÑ}½Ý¹•É}‘•¥Í¥½¸ô‘±•…¹9•áÐì•áÑ•É¹…±}¹½Ñ¥™¥…Ñ¥½¹}Í•¹Ðô‘™…±Í”ì±•…É¹¥¹}ÁÉ½µ½Ñ¥½¸ôÁÉ½Á½Í•‘}½¹±äœ(€€€€€€€€€€€•Ù•¹Ñ}¡…¥¹}¡•…‘}‰•™½É•}ÁÉ•Í•¹Ñ…Ñ¥½¸ô‘É•Á±…ä¹!•…‘!…Í (€€€€€€€ô(€€€€€€€€‘ÁÉ•Í•¹Ñ…Ñ¥½¹A…Ñ €ô)½¥¸µA…Ñ €‘Á…Ñ¡Ì¹AÉ•Í•¹Ñ…Ñ¥½¹Ì€ ‘5¥ÍÍ¥½¹%€¬€œ¹©Í½¸œ¤(€€€€€€€mMåÍÑ•´¹%<¹¥±•tèé]É¥Ñ•±±Q•áÐ ‘ÁÉ•Í•¹Ñ…Ñ¥½¹A…Ñ ° ‘ÁÉ•Í•¹Ñ…Ñ¥½¸ð½¹Ù•ÉÑQ¼µ)Í½¸€µ•ÁÑ €ÄØ¤±mMåÍÑ•´¹Q•áÐ¹UQá¹½‘¥¹tèé¹•Ü ‘™…±Í”¤¤(€€€€€€€€‘ÁÉ•Í•¹Ñ…Ñ¥½¹!…Í €ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹!…Í €µQ•áÐ€¡mMåÍÑ•´¹%<¹¥±•tèéI•…‘±±Q•áÐ ‘ÁÉ•Í•¹Ñ…Ñ¥½¹A…Ñ ¤¤(€€€€€€€€‘Á…å±½…€ôm½É‘•É•‘uìÁÉ•Í•¹Ñ…Ñ¥½¹}Á…Ñ ô‘ÁÉ•Í•¹Ñ…Ñ¥½¹A…Ñ ìÁÉ•Í•¹Ñ…Ñ¥½¹}Í¡„ÈÔØô‘ÁÉ•Í•¹Ñ…Ñ¥½¹!…Í ì½ÕÑ½µ”ô‘±•…¹=ÕÑ½µ”ìÕ¹É•Í½±Ù•ô‘±•…¹U¹É•Í½±Ù•ì¹•áÑ}½Ý¹•É}‘•¥Í¥½¸ô‘±•…¹9•áÐì•áÑ•É¹…±}¹½Ñ¥™¥…Ñ¥½¹}Í•¹Ðô‘™…±Í”ì±•…É¹¥¹}ÁÉ½µ½Ñ¥½¸ôÁÉ½Á½Í•‘}½¹±äœìÁ…É•¹Ñ}™¥¹…±}©Õ‘µ•¹Ðô‘ÑÉÕ”ô(€€€€€€€€‘•Ù•¹Ð€ô‘µÉ­¼äÕ5¥ÍÍ¥½¹MÑ…•QÉ…¹Í¥Ñ¥½¹U¹±½­•€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì€µ5¥ÍÍ¥½¸€‘µ¥ÍÍ¥½¸€µQ½MÑ…”€¹½Ñ¥™å}ÁÉ•Í•¹Ðœ€µÑ½É%€¡½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘=Ý¹•É%€µ5…á¥µÕµ1•¹Ñ €àÀ€µ…±±‰…¬€±½…±}½Ý¹•Èœ¤€µÑ½ÉI½±”€Á…É•¹Ñ}¥¹Ñ•É…Ñ½Èœ€µA…å±½…€‘Á…å±½…€µ1¥¹­•‘I••¥ÁÑÌ  ‘ÁÉ•Í•¹Ñ…Ñ¥½¹!…Í ¤(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì5¥ÍÍ¥½¹%ô‘5¥ÍÍ¥½¹%ìMÑ…”ô¹½Ñ¥™å}ÁÉ•Í•¹ÐœìMÑ…ÑÕÌô½µÁ±•Ñ”œìY•ÉÍ¥½¸ô‘•Ù•¹Ð¹¹•Ý}Ù•ÉÍ¥½¸ìAÉ•Í•¹Ñ…Ñ¥½¹A…Ñ ô‘ÁÉ•Í•¹Ñ…Ñ¥½¹A…Ñ ìAÉ•Í•¹Ñ…Ñ¥½¹I••¥ÁÐô‘ÁÉ•Í•¹Ñ…Ñ¥½¹!…Í ìáÑ•É¹…±9½Ñ¥™¥…Ñ¥½¹M•¹Ðô‘™…±Í”ô(€€€ô(€€€™¥¹…±±äìá¥ÐµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µ5ÕÑ•à€‘µÕÑ•àô)ô()™Õ¹Ñ¥½¸MÑ½ÀµÉ­¼äÕ5¥ÍÍ¥½¸ì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´ (€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘5¥ÍÍ¥½¹%°(€€€€€€€mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥um¥¹Ñt‘áÁ•Ñ•‘Y•ÉÍ¥½¸°(€€€€€€€mY…±¥‘…Ñ•M•Ð !½±œ°I•ÍÕµ”œ°‰½ÉÐœ¥umÍÑÉ¥¹t‘Ñ¥½¸€ô€!½±œ°(€€€€€€€mÍÑÉ¥¹t‘I•…Í½¸€ô€½Ý¹•É}É•ÅÕ•ÍÑ•œ°(€€€€€€€mÍÑÉ¥¹t‘=Ý¹•É%€ô€±½…±}½Ý¹•Èœ°(€€€€€€€mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð(€€€€¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘µÕÑ•à€ô€‘¹Õ±°(€€€ÑÉäì(€€€€€€€€‘µÕÑ•à€ô¹Ñ•ÈµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µMÑ…Ñ•I½½Ð€‘Á…Ñ¡Ì¹I½½Ð(€€€€€€€%¹¥Ñ¥…±¥é”µÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±MÑ…Ñ”€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€¥˜€ µ¹½Ð€‘É•Á±…ä¹Y…±¥¤ìÑ¡É½Ü€ 5¥ÍÍ¥½¸•Ù•¹Ð¡…¥¸¥Ì¥¹Ù…±¥è€œ€¬€ ‘É•Á±…ä¹ÉÉ½ÉÌ€µ©½¥¸€œì€œ¤¤ô(€€€€€€€€‘µ¥ÍÍ¥½¸€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹	å%€µI•Á±…ä€‘É•Á±…ä€µ5¥ÍÍ¥½¹%€‘5¥ÍÍ¥½¹%(€€€€€€€¥˜€ ‘µ¥ÍÍ¥½¸¹Ù•ÉÍ¥½¸€µ¹”€‘áÁ•Ñ•‘Y•ÉÍ¥½¸¤ìÑ¡É½Ü€5¥ÍÍ¥½¸Ù•ÉÍ¥½¸¥ÌÍÑ…±”ìÉ•™É•Í ‰•™½É”¡…¹¥¹œ¡½±ÍÑ…Ñ”¸œô(€€€€€€€€‘•Ù•¹ÑQåÁ”€ôÍÝ¥Ñ € ‘Ñ¥½¸¤ì€!½±œìµ¥ÍÍ¥½¹}¡•±ô€I•ÍÕµ”œìµ¥ÍÍ¥½¹}É•ÍÕµ•ô€‰½ÉÐœìµ¥ÍÍ¥½¹}…‰½ÉÑ•ôô(€€€€€€€¥˜€ ‘Ñ¥½¸€µ•Ä€!½±œ€µ…¹€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¹”€…Ñ¥Ù”œ¤ìÑ¡É½Ü€=¹±ä…¸…Ñ¥Ù”µ¥ÍÍ¥½¸µ…ä‰”¡•±¸œô(€€€€€€€¥˜€ ‘Ñ¥½¸€µ•Ä€I•ÍÕµ”œ€µ…¹€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¹”€¡•±œ¤ìÑ¡É½Ü€=¹±ä„¡•±µ¥ÍÍ¥½¸µ…ä‰”É•ÍÕµ•¸œô(€€€€€€€¥˜€ ‘Ñ¥½¸€µ•Ä€‰½ÉÐœ€µ…¹€‘µ¥ÍÍ¥½¸¹ÍÑ…ÑÕÌ€µ¥¸  ½µÁ±•Ñ”œ°…‰½ÉÑ•œ¤¤ìÑ¡É½Ü€Ñ•Éµ¥¹…°µ¥ÍÍ¥½¸…¹¹½Ð‰”…‰½ÉÑ•……¥¸¸œô(€€€€€€€€‘Á…å±½…€ôm½É‘•É•‘uìÉ•…Í½¸ô¡½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘I•…Í½¸€µ5…á¥µÕµ1•¹Ñ €ÈÐÀ€µ…±±‰…¬€½Ý¹•É}É•ÅÕ•ÍÑ•œ¤ì½Ý¹•É}…Ñ¥½¸ô‘ÑÉÕ”ìÍÑ…•}Õ¹¡…¹•ô‘ÑÉÕ”ô(€€€€€€€€‘•Ù•¹Ð€ô‘µÉ­¼äÕ5¥ÍÍ¥½¹Ù•¹ÑU¹±½­•€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì€µ5¥ÍÍ¥½¹%€‘5¥ÍÍ¥½¹%€µÙ•¹ÑQåÁ”€‘•Ù•¹ÑQåÁ”€µÉ½µMÑ…”€‘µ¥ÍÍ¥½¸¹ÍÑ…”€µQ½MÑ…”€‘µ¥ÍÍ¥½¸¹ÍÑ…”€µÑ½É%€¡½¹Ù•ÉÑQ¼µÉ­¼äÕ5¥ÍÍ¥½¹Q•áÐ€µY…±Õ”€‘=Ý¹•É%€µ5…á¥µÕµ1•¹Ñ €àÀ€µ…±±‰…¬€±½…±}½Ý¹•Èœ¤€µÑ½ÉI½±”€½Ý¹•Èœ€µ=‰©•Ñ¥Ù•!…Í €‘µ¥ÍÍ¥½¸¹½‰©•Ñ¥Ù•}Í¡„ÈÔØ€µáÁ•Ñ•‘Y•ÉÍ¥½¸€‘µ¥ÍÍ¥½¸¹Ù•ÉÍ¥½¸€µMÑ…ÑÕÌ€¡ÍÝ¥Ñ  ‘Ñ¥½¸¥ì!½±ì¡•±ôI•ÍÕµ”ì…Ñ¥Ù”ô‰½ÉÐì…‰½ÉÑ•õô¤€µA…å±½…€‘Á…å±½…(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•Ñuì5¥ÍÍ¥½¹%ô‘5¥ÍÍ¥½¹%ìMÑ…”ô‘µ¥ÍÍ¥½¸¹ÍÑ…”ìMÑ…ÑÕÌô‘•Ù•¹Ð¹ÍÑ…ÑÕÌìY•ÉÍ¥½¸ô‘•Ù•¹Ð¹¹•Ý}Ù•ÉÍ¥½¸ìÑ¥½¸ô‘Ñ¥½¸ô(€€€ô(€€€™¥¹…±±äìá¥ÐµÉ­¼äÕ5¥ÍÍ¥½¹5ÕÑ•à€µ5ÕÑ•à€‘µÕÑ•àô)ô()™Õ¹Ñ¥½¸Q•ÍÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±¡…¥¸ì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€ÑÉäì(€€€€€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€€€€É•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•ÑuìY…±¥ô‘É•Á±…ä¹Y…±¥ìÉÉ½ÉÌô‘É•Á±…ä¹ÉÉ½ÉÌìÙ•¹Ñ½Õ¹Ðô‘É•Á±…ä¹Ù•¹Ñ½Õ¹Ðì!•…‘!…Í ô‘É•Á±…ä¹!•…‘!…Í ì1¥µ¥Ñ…Ñ¥½¸ôM!´ÈÔØ¡…¥¹¥¹œ‘•Ñ•ÑÌ½É‘¥¹…Éä•‘¥ÑÌ‰ÕÐ¥Ì¹½Ð•áÑ•É¹…±±ä…¹¡½É•……¥¹ÍÐ„Í…µ”µÕÍ•È™Õ±°É•ÝÉ¥Ñ”¸œô(€€€ô(€€€…Ñ ìÉ•ÑÕÉ¸mÁÍÕÍÑ½µ½‰©•ÑuìY…±¥ô‘™…±Í”ìÉÉ½ÉÌõ  ‘|¹á•ÁÑ¥½¸¹5•ÍÍ…”¤ìÙ•¹Ñ½Õ¹ÐôÀì!•…‘!…Í ôœœì1¥µ¥Ñ…Ñ¥½¸ôY•É¥™¥…Ñ¥½¸™…¥±•±½Í•¸œôô)ô()™Õ¹Ñ¥½¸•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±MÑ…ÑÕÌì(€€€mµ‘±•Ñ	¥¹‘¥¹œ ¥t(€€€Á…É…´¡mA…É…µ•Ñ•È¡5…¹‘…Ñ½Éä¥umÍÑÉ¥¹t‘AÉ½©•ÑI½½Ð±mÍÑÉ¥¹t‘MÑ…Ñ•I½½Ð¤(€€€€‘Á…Ñ¡Ì€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µMÑ…Ñ•I½½Ð€‘MÑ…Ñ•I½½Ð(€€€€‘Á½±¥ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A½±¥ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð(€€€€‘É•Á±…ä€ô•ÐµÉ­¼äÕ5¥ÍÍ¥½¹I•Á±…ä€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð€µA…Ñ¡Ì€‘Á…Ñ¡Ì(€€€€‘½Á•¸€ô  ‘É•Á±…ä¹5¥ÍÍ¥½¹Ìð]¡•É”µ=‰©•Ðì€‘|¹ÍÑ…ÑÕÌ€µ¹½Ñ¥¸  ½µÁ±•Ñ”œ°…‰½ÉÑ•œ¤ô¤(€€€€‘…Ñ¥Ù”€ô¥˜€ ‘½Á•¸¹½Õ¹Ð€µ•Ä€Ä¤ì€‘½Á•¹lÁtô•±Í”ì€‘¹Õ±°ô(€€€€‘½ÁÌ€ô•ÐµÉ­¼äÕ=Á•É…Ñ¥½¹ÍMÑ…ÑÕÌ€µAÉ½©•ÑI½½Ð€‘AÉ½©•ÑI½½Ð(€€€mÁÍÕÍÑ½µ½‰©•Ñuì(€€€€€€€%¹¥Ñ¥…±¥é•€ôQ•ÍÐµA…Ñ €µ1¥Ñ•É…±A…Ñ €‘Á…Ñ¡Ì¹Ù•¹ÑÌ€µA…Ñ¡QåÁ”1•…˜(€€€€€€€¡…¥¹Y…±¥€ôm‰½½±t‘É•Á±…ä¹Y…±¥(€€€€€€€¡…¥¹ÉÉ½ÉÌ€ô  ‘É•Á±…ä¹ÉÉ½ÉÌ¤(€€€€€€€Ù•¹Ñ½Õ¹Ð€ôm¥¹Ñt‘É•Á±…ä¹Ù•¹Ñ½Õ¹Ð(€€€€€€€!•…‘!…Í €ômÍÑÉ¥¹t‘É•Á±…ä¹!•…‘!…Í (€€€€€€€5¥ÍÍ¥½¹½Õ¹Ð€ô  ‘É•Á±…ä¹5¥ÍÍ¥½¹Ì¤¹½Õ¹Ð(€€€€€€€=Á•¹5¥ÍÍ¥½¹½Õ¹Ð€ô€‘½Á•¸¹½Õ¹Ð(€€€€€€€Ñ¥Ù•5¥ÍÍ¥½¸€ô€‘…Ñ¥Ù”(€€€€€€€5¥ÍÍ¥½¹Ì€ô  ‘É•Á±…ä¹5¥ÍÍ¥½¹Ì¤(€€€€€€€MÑ…•Ì€ô  ‘Á½±¥ä¹ÍÑ…•Ì¤(€€€€€€€Q•…µ1…¹•Ì€ô  ‘Á½±¥ä¹Ñ•…µ}±…¹•Ì¤(€€€€€€€±±½Ý•‘=Á•É…Ñ¥½¹Í…Á…‰¥±¥Ñ¥•Ì€ô  ‘Á½±¥ä¹…±±½Ý•‘}½Á•É…Ñ¥½¹Í}…Á…‰¥±¥Ñ¥•Ì¤(€€€€€€€=Á•É…Ñ¥½¹Ì€ô€‘½ÁÌ(€€€€€€€áÑ•É¹…±9½Ñ¥™¥…Ñ¥½¹•™…Õ±Ð€ô€‘™…±Í”(€€€€€€€1•…É¹¥¹AÉ½µ½Ñ¥½¹•™…Õ±Ð€ô€ÁÉ½Á½Í•‘}½¹±äœ(€€€ô)ô()áÁ½ÉÐµ5½‘Õ±•5•µ‰•È€µÕ¹Ñ¥½¸•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A…Ñ¡Ì°•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±A½±¥ä°9•ÜµÉ­¼äÕ5¥ÍÍ¥½¸°MÑ…ÉÐµÉ­¼äÕ5¥ÍÍ¥½¹A±…¸°‘µÉ­¼äÕ5¥ÍÍ¥½¹ÕÑä°Må¹ŒµÉ­¼äÕ5¥ÍÍ¥½¹á•ÕÑ¥½¸°½¹™¥É´µÉ­¼äÕ5¥ÍÍ¥½¹Y•É¥™¥…Ñ¥½¸°½µÁ±•Ñ”µÉ­¼äÕ5¥ÍÍ¥½¸°MÑ½ÀµÉ­¼äÕ5¥ÍÍ¥½¸°Q•ÍÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±¡…¥¸°•ÐµÉ­¼äÕ5¥ÍÍ¥½¹½¹ÑÉ½±MÑ…ÑÕÌ