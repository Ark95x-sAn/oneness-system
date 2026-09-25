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
    return Get-Content -Raw -LiteralPath $Path -ErrorAction Stop | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String -ErrorAction Stop
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
                $event = $line | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String -ErrorAction Stop
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
        completed = @(Get-ChildItem -LiteralPath $Paths.Completed -Filter '*.json' ×]tîÚ$z{-®éÜj×†–âÒvWBÔ&¶ó“T÷5&V6V—D6†–å7FGW2ÕF‡2GF‡0¢–b‚Öæ÷BF6†–âåfÆ–B’°¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâ‚w&V6V—Eö6†–åö–çfÆ–C¢r²F6†–âäW'&÷"’ÔfVÇD6Æ72vVF—Eö–çFVw&—G’p¢F‡&÷r%&V6V—B6†–â—2–çfÆ–C¢B‚F6†–âäW'&÷"’ ¢Ğ¢–b…¶&ööÅÒF6öçG&öÂæ¶–ÆÅöÆF6†VBÖ÷"·7G&–æuÒF6öçG&öÂæFW6—&VE÷7FFRÖæRw'Vææ–ærrÖ÷"·7G&–æuÒG'VçF–ÖRæ6—&7V—E÷7FFRÖæRv6Æ÷6VBr’°¢&WGW&â·67W7FöÖö&¦V7EÔ²7–6ÆT–CÒF7–6ÆT–C²7FGW3ÒwW6VBs²&ö6W76VCÔ‚“²&V6öãÕ·7G&–æuÒF6öçG&öÂç&V6öã²÷W&F–öç3ÔvWBÔ&¶ó“T÷W&F–öç57FGW2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BĞ¢Ğ¢–b‚FçVÆÂÖWFÆV6RÖ÷"·7G&–æuÒFÆV6Rç7FGW2ÖæRv7F—fRrÖ÷"¶–çEÒFÆV6RçöÆ–7•öWö6‚ÖæR¶–çEÒF6öçG&öÂçöÆ–7•öWö6‚’°¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâvÆV6UöÖ—76–æuö–æ7F—fUö÷%öWö6…öÖ—6ÖF6‚rÔfVÇD6Æ72vWF†÷&—G•öf–ÇW&Rp¢F‡&÷ruF†R7F—fRÆV6R—2Ö—76–ærÂ–æ7F—fRÂ÷"&÷VæBFòæ÷F†W"öÆ–7’Wö6‚âp¢Ğ¢FÆV6TW‡—'’Ò´FFUF–ÖTöfg6WEÓ£¤Ö–åfÇVP¢–b‚Öæ÷B´FFUF–ÖTöfg6WEÓ£¥G'•'6R…·7G&–æuÒFÆV6RæW‡—&W5öBÅ·&VeÒFÆV6TW‡—'’’Ö÷"FÆV6TW‡—'’ÖÆR´FFUF–ÖTöfg6WEÓ£¥WF4æ÷r’°¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâvÆV6UöW‡—&VBrÔfVÇD6Æ72vWF†÷&—G•öf–ÇW&Rp¢F‡&÷ruF†R÷W&F–öç2eÆV6RW‡—&VBâp¢Ğ ¢Gv÷&¶–ætf–ÆW2Ò„vWBÔ6†–ÆD—FVÒÔÆ—FW&ÅF‚GF‡2åv÷&¶–ærÔf–ÇFW"r¢æ§6öârÔf–ÆRÔW'&÷$7F–öâ6–ÆVçFÇ”6öçF–çVR¢–b‚Gv÷&¶–ætf–ÆW2ä6÷VçBÖwB’°¢f÷&V6‚‚Gv÷&¶–ætf–ÆR–âGv÷&¶–ætf–ÆW2’°¢FGWG’Ò&VBÔ&¶ó“T÷4§6öâÕF‚Gv÷&¶–ætf–ÆRägVÆÄæÖP¢FGWG’ç7FGW2Òv†VÆBp¢FGWG’æ†öÆE÷&V6öâÒwVæ6W'F–åögFW%÷v÷&¶W%ö–çFW''WF–öâp¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚Gv÷&¶–ætf–ÆRägVÆÄæÖRÕfÇVRFGWG¢FçVÆÂÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RGv÷&¶–ætf–ÆRägVÆÄæÖRÔFW7F–æF–öäF—&V7F÷'’GF‡2ä†VÆ@¢Ğ¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâwVæ6W'F–å÷v÷&¶–æuöGWG•ögFW%ö–çFW''WF–öârÔfVÇD6Æ72v7&6…÷&V6÷fW'’p¢F‡&÷rt&Wf–÷W6Ç’6Æ–ÖVBGWG’†BVæ6W'F–â÷7B×7FFS²÷W&F–öç27F÷VBf÷"&Wf–Wrâp¢Ğ ¢6WBÔ&¶ó“T÷4†V'F&VBÕF‡2GF‡2Õv÷&¶W$–ç7Fæ6RGv÷&¶W$–ç7Fæ6RÔ7–6ÆT–BF7–6ÆT–BÕ7FGW2w'Vææ–ærp¢G&W6÷W&6U6æ6†÷BÒvWBÔ&¶ó“T÷5&W6÷W&6U6æ6†÷BÕ&ö¦V7E&ö÷BE&ö¦V7E&ö÷@¢FFÖ—76–öâÒFW7BÔ&¶ó“T÷5&W6÷W&6TFÖ—76–öâÕöÆ–7’GöÆ–7’Õ6æ6†÷BG&W6÷W&6U6æ6†÷@¢–b‚Öæ÷BFFÖ—76–öâäFÖ—GFVB’°¢6WBÔ&¶ó“T÷4†V'F&VBÕF‡2GF‡2Õv÷&¶W$–ç7Fæ6RGv÷&¶W$–ç7Fæ6RÔ7–6ÆT–BF7–6ÆT–BÕ7FGW2w&W6÷W&6Uö†öÆBrÔFWF–Ç2…¶÷&FW&VEÔ²&V6öç3Ô‚FFÖ—76–öâå&V6öç2’Ò¢&WGW&â·67W7FöÖö&¦V7EÔ²7–6ÆT–CÒF7–6ÆT–C²7FGW3Òw&W6÷W&6Uö†öÆBs²&ö6W76VCÔ‚“²&V6öãÒ‚FFÖ—76–öâå&V6öç2Ö¦ö–ârÂr“²÷W&F–öç3ÔvWBÔ&¶ó“T÷W&F–öç57FGW2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BĞ¢Ğ ¢G66†VGVÆVBÒFBÔ&¶ó“T÷5&V7W'&–ætGWF–W2ÕF‡2GF‡2ÕöÆ–7’GöÆ–7¢GVæF–ærÒ´6öÆÆV7F–öç2ävVæW&–2äÆ—7E¶ö&¦V7EÕÓ£¦æWr‚¢f÷&V6‚‚Ff–ÆR–â„vWBÔ6†–ÆD—FVÒÔÆ—FW&ÅF‚GF‡2åVæF–ærÔf–ÇFW"r¢æ§6öârÔf–ÆRÔW'&÷$7F–öâ7F÷’’°¢FGWG’Ò&VBÔ&¶ó“T÷4§6öâÕF‚Ff–ÆRägVÆÄæÖP¢Fæ÷D&Vf÷&U&VG’ÒGG'VP¢–b‚Öæ÷B·7G&–æuÓ£¤—4çVÆÄ÷%v†—FU76R…·7G&–æuÒFGWG’ææ÷Eö&Vf÷&R’’°¢Fæ÷D&Vf÷&RÒ´FFUF–ÖTöfg6WEÓ£¤Ö–åfÇVP¢–b…´FFUF–ÖTöfg6WEÓ£¥G'•'6R…·7G&–æuÒFGWG’ææ÷Eö&Vf÷&RÅ·&VeÒFæ÷D&Vf÷&R’’²Fæ÷D&Vf÷&U&VG’ÒFæ÷D&Vf÷&RÖÆR´FFUF–ÖTöfg6WEÓ£¥WF4æ÷rĞ¢Ğ¢–b‚Fæ÷D&Vf÷&U&VG’’²GVæF–æräFB…·67W7FöÖö&¦V7EÔ²FƒÒFf–ÆRägVÆÄæÖS²GWG“ÒFGWG’Ò’Ğ¢Ğ¢G6VÆV7FVBÒ‚GVæF–ærÂ6÷'BÔö&¦V7B´W‡&W76–öã×µ¶–çEÒEòäGWG’ç&–÷&—G—Ó´66VæF–æsÒGG'VWÒÂ´W‡&W76–öã×µ·7G&–æuÒEòäGWG’æ7&VFVEöGÓ´66VæF–æsÒGG'VWÒÂ6VÆV7BÔö&¦V7BÔf—'7B…¶–çEÒGöÆ–7’ç66†VGVÆW"æÖ…öGWF–W5÷W%ö7–6ÆR’¢f÷&V6‚‚F—FVÒ–âG6VÆV7FVB’°¢F6öçG&öÂÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2ä6öçG&öÀ¢FÆV6RÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2äÆV6P¢–b…¶&ööÅÒF6öçG&öÂæ¶–ÆÅöÆF6†VBÖ÷"·7G&–æuÒF6öçG&öÂæFW6—&VE÷7FFRÖæRw'Vææ–ærr’²'&V²Ğ¢F6†–âÒvWBÔ&¶ó“T÷5&V6V—D6†–å7FGW2ÕF‡2GF‡0¢–b‚Öæ÷BF6†–âåfÆ–B’°¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâ‚w&V6V—Eö6†–åö6†ævVEöGW&–æuö7–6ÆS¢r²F6†–âäW'&÷"’ÔGWG”–B…·7G&–æuÒF—FVÒäGWG’æGWG•ö–B’ÔfVÇD6Æ72vVF—Eö–çFVw&—G’p¢'&V°¢Ğ¢FGWG’ÒF—FVÒäGWG¢F6&–Æ—G”FVf–æ—F–öâÒvWBÔ&¶ó“T÷46&–Æ—G’ÕöÆ–7’GöÆ–7’Ô6&–Æ—G”–B…·7G&–æuÒFGWG’æ6&–Æ—G’¢–b‚FçVÆÂÖWF6&–Æ—G”FVf–æ—F–öâ’°¢FGWG’ç7FGW2Òv†VÆBs²FGWG’æ†öÆE÷&V6öâÒwVæ¶æ÷våö6&–Æ—G’p¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚F—FVÒåF‚ÕfÇVRFGWG¢FçVÆÂÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RF—FVÒåF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2ä†VÆ@¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâwVæ¶æ÷våö6&–Æ—G•ö–å÷VWVRrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’ÔfVÇD6Æ72wöÆ–7•÷f–öÆF–öâp¢'&V°¢Ğ¢G&VfÆ–v‡BÒ–çfö¶RÔ&¶ó“T÷5&VfÆ–v‡E&Wf–WrÔGWG’FGWG’Ô6&–Æ—G”FVf–æ—F–öâF6&–Æ—G”FVf–æ—F–öâÔ6öçG&öÂF6öçG&öÂÔÆV6RFÆV6RÕöÆ–7’GöÆ–7¢–b‚Öæ÷BG&VfÆ–v‡Bç76VB’°¢FGWG’ç7FGW2Òv†VÆBs²FGWG’æ†öÆE÷&V6öâÒw&VfÆ–v‡E÷&V¦V7FVBs²FGWG’ç&VfÆ–v‡BÒG&VfÆ–v‡@¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚F—FVÒåF‚ÕfÇVRFGWG¢FçVÆÂÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RF—FVÒåF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2ä†VÆ@¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâ‚w&VfÆ–v‡E÷&V¦V7FVC¢r²‚G&VfÆ–v‡Bç&V6öç2Ö¦ö–ârÂr’’ÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’ÔfVÇD6Æ72wöÆ–7•÷f–öÆF–öâp¢'&V°¢Ğ ¢Gv÷&¶–æuF‚ÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RF—FVÒåF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2åv÷&¶–æp¢FGWG’ç7FGW2Òwv÷&¶–ærp¢FGWG’æGFV×G2Ò¶–çEÒFGWG’æGFV×G2²¢FGWG’æfVæ6U÷Fö¶VâÒ¶–çEÒFGWG’æfVæ6U÷Fö¶Vâ²¢FGWG’æ6Æ–ÖVEöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢FGWG’çv÷&¶W%ö–ç7Fæ6RÒGv÷&¶W$–ç7Fæ6P¢FGWG’æÆV6Uö–BÒ·7G&–æuÒFÆV6RæÆV6Uö–@¢FGWG’çöÆ–7•öWö6‚Ò¶–çEÒF6öçG&öÂçöÆ–7•öWö6€¢FGWG’ç&VfÆ–v‡BÒG&VfÆ–v‡@¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚Gv÷&¶–æuF‚ÕfÇVRFGWG¢FçVÆÂÒFBÔ&¶ó“T÷4WfVçBÕF‡2GF‡2ÔWfVçEG—RvGWG•ö6Æ–ÖVBrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’Õ–ÆöB…¶÷&FW&VEÔ²6&–Æ—G“ÒFGWG’æ6&–Æ—G“²ÆV6Uö–CÒFGWG’æÆV6Uö–C²öÆ–7•öWö6ƒÒFGWG’çöÆ–7•öWö6ƒ²fVæ6U÷Fö¶VãÒFGWG’æfVæ6U÷Fö¶Vã²&WVW7Eö†6ƒÒFGWG’ç&WVW7Eö†6‚Ò ¢G'’°¢F6öçG&öÄ&Vf÷&TVffV7BÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2ä6öçG&öÀ¢F6†–ä&Vf÷&TVffV7BÒvWBÔ&¶ó“T÷5&V6V—D6†–å7FGW2ÕF‡2GF‡0¢–b…¶&ööÅÒF6öçG&öÄ&Vf÷&TVffV7Bæ¶–ÆÅöÆF6†VBÖ÷"·7G&–æuÒF6öçG&öÄ&Vf÷&TVffV7BæFW6—&VE÷7FFRÖæRw'Vææ–ærr’²F‡&÷rv¶–ÆÅöÆF6…ö6†ævVEö&Vf÷&UöVffV7BrĞ¢–b‚Öæ÷BF6†–ä&Vf÷&TVffV7BåfÆ–B’²F‡&÷rw&V6V—Eö6†–åö–çfÆ–Eö&Vf÷&UöVffV7BrĞ¢G7F÷vF6‚Òµ7—7FVÒäF–væ÷7F–72å7F÷vF6…Ó£¥7F'DæWr‚¢G&W7VÇBÒ–çfö¶RÔ&¶ó“T÷46&–Æ—G’Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕF‡2GF‡2ÕöÆ–7’GöÆ–7’Ô6&–Æ—G”FVf–æ—F–öâF6&–Æ—G”FVf–æ—F–öâÔGWG’FGWG¢G7F÷vF6‚å7F÷‚¢G&Wf–WrÒ–çfö¶RÔ&¶ó“T÷5÷7E&Wf–WrÕF‡2GF‡2ÔGWG’FGWG’Ô6&–Æ—G”FVf–æ—F–öâF6&–Æ—G”FVf–æ—F–öâÕ&W7VÇBG&W7VÇBÔGW&F–öå6V6öæG2G7F÷vF6‚äVÆ6VBåF÷FÅ6V6öæG2Õ&VfÆ–v‡BG&VfÆ–v‡@¢G&Wf–WuF‚Ò¦ö–âÕF‚GF‡2å&Wf–Ww2‚…·7G&–æuÒFGWG’æGWG•ö–B’²ræ§6öâr¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚G&Wf–WuF‚ÕfÇVR…¶÷&FW&VEÔ²66†VÖ÷fW'6–öãÓ²GWG•ö–CÒFGWG’æGWG•ö–C²6&–Æ—G“ÒFGWG’æ6&–Æ—G“²GW&F–öå÷6V6öæG3Õ¶ÖF…Ó£¥&÷VæB‚G7F÷vF6‚äVÆ6VBåF÷FÅ6V6öæG2Ã2“²FV6—6–öãÒG&Wf–WræFV6—6–öã²&VçEöf–æÅö§VFvÖVçE÷&WV—&VCÒGG'VS²&Wf–Ww3ÒG&Wf–Wrç&Wf–Ww3²7&VFVEöCÕ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr’Ò¢G&Wf–Wt†6‚Ò„vWBÔf–ÆT†6‚ÔÆ—FW&ÅF‚G&Wf–WuF‚ÔÆv÷&—F†Ò4„#Sb’ä†6‚åFôÆ÷vW$–çf&–çB‚¢–b‚Öæ÷BG&Wf–Wrç76VB’°¢FGWG’ç7FGW2Òv†VÆBs²FGWG’æ†öÆE÷&V6öâÒw÷7E÷&Wf–Wu÷&V¦V7FVBs²FGWG’ç&W7VÇBÒG&W7VÇC²FGWG’ç&Wf–Wu÷F‚ÒG&Wf–WuFƒ²FGWG’ç&Wf–Wuö†6‚ÒG&Wf–Wt†6€¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚Gv÷&¶–æuF‚ÕfÇVRFGWG¢FçVÆÂÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RGv÷&¶–æuF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2ä†VÆ@¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâw÷7E÷&Wf–Wu÷&V¦V7FVBrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’ÔfVÇD6Æ72vGfW'6U÷&Wf–Wrp¢'&V°¢Ğ¢FGWG’ç7FGW2ÒwfW&–f–VBp¢FGWG’æ6ö×ÆWFVEöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢FGWG’æGW&F–öå÷6V6öæG2Ò¶ÖF…Ó£¥&÷VæB‚G7F÷vF6‚äVÆ6VBåF÷FÅ6V6öæG2Ã2¢FGWG’ç&W7VÇBÒG&W7VÇ@¢FGWG’ç&Wf–Wu÷F‚ÒG&Wf–WuF€¢FGWG’ç&Wf–Wuö†6‚ÒG&Wf–Wt†6€¢FGWG’ç&VçEöf–æÅö§VFvÖVçE÷&WV—&VBÒGG'VP¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚Gv÷&¶–æuF‚ÕfÇVRFGWG¢F6ö×ÆWFVEF‚ÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RGv÷&¶–æuF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2ä6ö×ÆWFV@¢G'’°¢G&V6V—BÒFBÔ&¶ó“T÷4WfVçBÕF‡2GF‡2ÔWfVçEG—RvGWG•÷fW&–f–VBrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’Õ–ÆöB…¶÷&FW&VEÔ²6&–Æ—G“ÒFGWG’æ6&–Æ—G“²&WVW7Eö†6ƒÒFGWG’ç&WVW7Eö†6ƒ²fVæ6U÷Fö¶VãÒFGWG’æfVæ6U÷Fö¶Vã²'F–f7Eö†6†W3ÒG&W7VÇBä'F–f7D†6†W3²&Wf–Wuö†6ƒÒG&Wf–Wt†6ƒ²GW&F–öå÷6V6öæG3ÒFGWG’æGW&F–öå÷6V6öæG3²&VçEöf–æÅö§VFvÖVçE÷&WV—&VCÒGG'VRÒ¢G&ö6W76VBäFB…·67W7FöÖö&¦V7EÔ²GWG•ö–CÒFGWG’æGWG•ö–C²6&–Æ—G“ÒFGWG’æ6&–Æ—G“²7FGW3ÒwfW&–f–VBs²&V6V—Eö†6ƒÒG&V6V—BæWfVçEö†6ƒ²6ö×ÆWFVE÷FƒÒF6ö×ÆWFVEF‚Ò¢Ğ¢6F6‚°¢F†VÆEF‚ÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RF6ö×ÆWFVEF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2ä†VÆ@¢F†VÆDGWG’Ò&VBÔ&¶ó“T÷4§6öâÕF‚F†VÆEF€¢F†VÆDGWG’ç7FGW2Òv†VÆBs²F†VÆDGWG’æ†öÆE÷&V6öâÒv6ö×ÆWF–öå÷&V6V—Eöf–ÆVBp¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚F†VÆEF‚ÕfÇVRF†VÆDGWG¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâv6ö×ÆWF–öå÷&V6V—Eöf–ÆVBrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’ÔfVÇD6Æ72vVF—Eöf–ÇW&Rp¢'&V°¢Ğ¢G'VçF–ÖRÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2å'VçF–ÖP¢G'VçF–ÖRæGWF–W5ö6ö×ÆWFVBÒ¶–çEÒG'VçF–ÖRæGWF–W5ö6ö×ÆWFVB²¢G'VçF–ÖRæ6öç6V7WF—fUöf–ÇW&W2Ò ¢G'VçF–ÖRçWFFVEöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚GF‡2å'VçF–ÖRÕfÇVRG'VçF–ÖP¢FÆV6RÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2äÆV6P¢GFöF’Ò´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råWF4FFUF–ÖRåFõ7G&–ær‚w———’ÔÔÒÖFBr¢–b…·7G&–æuÒFÆV6Ræ–çfö6F–öå÷v–æF÷uöFFRÖæRGFöF’’²FÆV6Ræ–çfö6F–öå÷v–æF÷uöFFRÒGFöF“²FÆV6Ræ–çfö6F–öç5÷FöF’ÒĞ¢FÆV6Ræ–çfö6F–öç5÷FöF’Ò¶–çEÒFÆV6Ræ–çfö6F–öç5÷FöF’²¢–b…¶–çEÒFÆV6Ræ–çfö6F–öç5÷FöF’ÖwB¶–çEÒFÆV6RæÖ…ö–çfö6F–öç5÷W%öF’’°¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâvF–Ç•ö–çfö6F–öåö'VFvWEöW†6VVFVBrÔfVÇD6Æ72w&W6÷W&6Uö'VFvWBp¢'&V°¢Ğ¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚GF‡2äÆV6RÕfÇVRFÆV6P¢Ğ¢6F6‚°¢–b…FW7BÕF‚ÔÆ—FW&ÅF‚Gv÷&¶–æuF‚ÕF…G—RÆVb’°¢Ff–ÆVDGWG’Ò&VBÔ&¶ó“T÷4§6öâÕF‚Gv÷&¶–æuF€¢Ff–ÆVDGWG’ç7FGW2Òvf–ÆVBp¢Ff–ÆVDGWG’æf–ÇW&U÷&V6öâÒ‚‚EòäW†6WF–öâäÖW76vR×&WÆ6RuµÇSÕÇSeÇSteÒ²rÂrr’×&WÆ6RuÇ2²rÂrr’åG&–Ò‚¢Ff–ÆVDGWG’æf–ÆVEöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚Gv÷&¶–æuF‚ÕfÇVRFf–ÆVDGWG¢FçVÆÂÒÖ÷fRÔ&¶ó“T÷4GWG’Õ6÷W&6RGv÷&¶–æuF‚ÔFW7F–æF–öäF—&V7F÷'’GF‡2äf–ÆV@¢Ğ¢G'’²FçVÆÂÒFBÔ&¶ó“T÷4WfVçBÕF‡2GF‡2ÔWfVçEG—RvGWG•öf–ÆVBrÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’Õ–ÆöB…¶÷&FW&VEÔ²6&–Æ—G“ÒFGWG’æ6&–Æ—G“²&V6öãÒEòäW†6WF–öâäÖW76vRÒ’Ò6F6‚²Ğ¢–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâ‚vGWG•öf–ÆVC¢r²EòäW†6WF–öâäÖW76vR’ÔGWG”–B…·7G&–æuÒFGWG’æGWG•ö–B’ÔfVÇD6Æ72v†æFÆW%öf–ÇW&Rp¢'&V°¢Ğ¢Ğ ¢G'VçF–ÖRÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2å'VçF–ÖP¢–b…·7G&–æuÒG'VçF–ÖRæ6—&7V—E÷7FFRÖWv6Æ÷6VBr’°¢G'VçF–ÖRæ7–6ÆW5ö6ö×ÆWFVBÒ¶–çEÒG'VçF–ÖRæ7–6ÆW5ö6ö×ÆWFVB²¢G'VçF–ÖRæÆ7Eö7–6ÆUöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢G'VçF–ÖRçWFFVEöBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷råFõ7G&–ær‚vòr¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚GF‡2å'VçF–ÖRÕfÇVRG'VçF–ÖP¢FÆV6RÒ&VBÔ&¶ó“T÷4§6öâÕF‚GF‡2äÆV6P¢FÆV6RæW‡—&W5öBÒ´FFUF–ÖTöfg6WEÓ£¥WF4æ÷räFD†÷W'2…¶F÷V&ÆUÒGöÆ–7’æÆV6RæGW&F–öåö†÷W'2’åFõ7G&–ær‚vòr¢w&—FRÔ&¶ó“T÷4§6öäFöÖ–2ÕF‚GF‡2äÆV6RÕfÇVRFÆV6P¢6WBÔ&¶ó“T÷4†V'F&VBÕF‡2GF‡2Õv÷&¶W$–ç7Fæ6RGv÷&¶W$–ç7Fæ6RÔ7–6ÆT–BF7–6ÆT–BÕ7FGW2v–FÆRrÔFWF–Ç2…¶÷&FW&VEÔ²&ö6W76VCÒG&ö6W76VBä6÷VçC²66†VGVÆVCÒG66†VGVÆVBÒ¢Ğ¢VÇ6R°¢6WBÔ&¶ó“T÷4†V'F&VBÕF‡2GF‡2Õv÷&¶W$–ç7Fæ6RGv÷&¶W$–ç7Fæ6RÔ7–6ÆT–BF7–6ÆT–BÕ7FGW2v6—&7V—Eö÷VârÔFWF–Ç2…¶÷&FW&VEÔ²&ö6W76VCÒG&ö6W76VBä6÷VçBÒ¢Ğ¢&WGW&â·67W7FöÖö&¦V7EÔ²7–6ÆT–CÒF7–6ÆT–C²7FGW3ÒB†–b…·7G&–æuÒG'VçF–ÖRæ6—&7V—E÷7FFRÖWv6Æ÷6VBr’²v6ö×ÆWFVBwÒVÇ6R²v6—&7V—Eö÷VâwÒ“²66†VGVÆVCÒG66†VGVÆVC²&ö6W76VCÒG&ö6W76VBåFô'&’‚“²÷W&F–öç3ÔvWBÔ&¶ó“T÷W&F–öç57FGW2Õ&ö¦V7E&ö÷BE&ö¦V7E&ö÷BÕ7FFU&ö÷BE7FFU&ö÷BĞ¢Ğ¢6F6‚°¢–b‚FçVÆÂÖæRGF‡2ÖæB…FW7BÕF‚ÔÆ—FW&ÅF‚GF‡2ä6öçG&öÂÕF…G—RÆVb’’°¢G'’²–çfö¶RÔ&¶ó“T÷5G&—6—&7V—BÕF‡2GF‡2Õ&V6öâ‚v7–6ÆUöW†6WF–öã¢r²EòäW†6WF–öâäÖW76vR’ÔfVÇD6Æ72v7–6ÆUöW†6WF–öârÒ6F6‚²Ğ¢G'’²6WBÔ&¶ó“T÷4†V'F&VBÕF‡2GF‡2Õv÷&¶W$–ç7Fæ6RGv÷&¶W$–ç7Fæ6RÔ7–6ÆT–BF7–6ÆT–BÕ7FGW2vfVÇFVBrÔFWF–Ç2…¶÷&FW&VEÔ²&V6öãÒEòäW†6WF–öâäÖW76vRÒ’Ò6F6‚²Ğ¢Ğ¢F‡&÷p¢Ğ¢f–æÆÇ’²W†—BÔ&¶ó“T÷W&F–öç4×WFW‚Ô×WFW‚F×WFW‚Ğ§Ğ ¤W‡÷'BÔÖöGVÆTÖVÖ&W"ÔgVæ7F–öâvWBÔ&¶ó“T÷W&F–öç5F‡2ÂvWBÔ&¶ó“T÷W&F–öç5öÆ–7’Â–æ—F–Æ—¦RÔ&¶ó“T÷W&F–öç2ÂVæ&ÆRÔ&¶ó“T÷W&F–öç2Â7F÷Ô&¶ó“T÷W&F–öç2ÂvWBÔ&¶ó“T÷W&F–öç57FGW2ÂFW7BÔ&¶ó“T÷W&F–öç5&V6V—D6†–âÂæWrÔ&¶ó“T÷W&F–öç4GWG’Â–çfö¶RÔ&¶ó“T÷W&F–öç47–6ÆP