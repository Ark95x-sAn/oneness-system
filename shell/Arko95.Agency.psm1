Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1')

function Get-Arko95AgencyHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-Arko95AgencyProperty {
    param([AllowNull()]$InputObject,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Read-Arko95AgencyJson {
    param([Parameter(Mandatory)][string]$Path,[int64]$MaximumBytes=8388608)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Length -gt $MaximumBytes) { throw "Agency state exceeds its size limit: $Path" }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Agency state cannot be read through a reparse point: $Path" }
    return Get-Content -Raw -LiteralPath $Path -ErrorAction Stop | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String -ErrorAction Stop
}

function Write-Arko95AgencyJsonAtomic {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $directoryItem = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
    if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Agency output directory is a reparse point: $directory" }
    if (Test-Path -LiteralPath $Path) {
        $target = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Agency output target is a reparse point: $Path" }
    }
    $temporary = Join-Path $directory ('.{0}.{1}.tmp' -f [IO.Path]::GetFileName($Path),[guid]::NewGuid().ToString('N'))
    try {
        $json = $Value | ConvertTo-Json -Depth 32
        [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path,$true)
    }
    finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
}

function Get-Arko95AgencyPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot)
    $core = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = Join-Path $core.StateDir 'agency' }
    $scopeMarker = Join-Path $StateRoot '.scope'
    $resolvedMarker = Resolve-Arko95StateWritePath -ProjectRoot $ProjectRoot -RequestedPath $scopeMarker -DefaultPath $scopeMarker
    $root = Split-Path -Parent $resolvedMarker
    [pscustomobject]@{
        Root = $root
        Policy = Join-Path $core.Root 'config\agency.json'
        Events = Join-Path $root 'events.jsonl'
        ChainHead = Join-Path $root 'chain-head.json'
        Snapshots = Join-Path $root 'snapshots'
        LatestCatalog = Join-Path $root 'latest-catalog.json'
        LatestBacklog = Join-Path $root 'latest-backlog.json'
    }
}

function Test-Arko95AgencyRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return $false }
    $segments = @($Path -split '[\\/]' | Where-Object { $_ -notin @('','.') })
    return @($segments | Where-Object { $_ -eq '..' }).Count -eq 0
}

function Get-Arko95AgencyRequiredForbiddenRoots {
    return @(
        'OneDrive\Desktop\rsb case',
        '.ssh',
        '.gnupg',
        '.codex',
        'Downloads',
        'AppData',
        'OneDrive\Personal Vault'
    )
}

function Get-Arko95AgencyExtensionBucket {
    param([AllowEmptyString()][string]$Name)
    $extension = ([IO.Path]::GetExtension($Name)).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($extension)) { return '[none]' }
    if ($extension -in @('.ps1','.psm1','.psd1','.py','.js','.jsx','.ts','.tsx','.cs','.cpp','.c','.h','.java','.go','.rs','.rb','.php','.sql','.html','.css','.scss')) { return '[code]' }
    if ($extension -in @('.md','.txt','.rtf','.pdf','.doc','.docx','.odt','.ppt','.pptx')) { return '[document]' }
    if ($extension -in @('.json','.jsonl','.csv','.tsv','.xml','.yaml','.yml','.toml','.ini','.config','.log')) { return '[structured]' }
    if ($extension -in @('.png','.jpg','.jpeg','.gif','.webp','.bmp','.svg','.ico','.tif','.tiff','.mp3','.wav','.m4a','.mp4','.mov','.avi','.mkv')) { return '[media]' }
    if ($extension -in @('.zip','.7z','.rar','.tar','.gz','.bz2','.xz')) { return '[archive]' }
    if ($extension -in @('.exe','.msi','.msix','.dll','.sys','.appx','.appxbundle')) { return '[binary]' }
    return '[other]'
}

function Get-Arko95AgencyPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $paths = Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot
    $policy = Read-Arko95AgencyJson -Path $paths.Policy -MaximumBytes 1048576
    if ($null -eq $policy -or [int]$policy.schema_version -ne 1) { throw 'Agency policy is missing or unsupported.' }
    if ([string]$policy.mode -ne 'metadata_only' -or [string]$policy.default_effect -ne 'proposal_only' -or [string]$policy.authority -ne 'none') {
        throw 'Agency must remain metadata-only, proposal-only, and zero-authority.'
    }
    $rules = $policy.catalog_rules
    if ([string]$rules.path_storage -ne 'sha256_only' -or [bool]$rules.inspect_file_contents -or [bool]$rules.compute_content_hashes -or [bool]$rules.follow_reparse_points) {
        throw 'Agency catalog rules attempted to retain paths, read content, hash content, or follow reparse points.'
    }
    if ([int]$rules.maximum_runtime_seconds -lt 1 -or [int]$rules.maximum_runtime_seconds -gt 120) { throw 'Agency runtime boundary is invalid.' }
    if ([int]$rules.maximum_sources_per_cycle -lt 1 -or [int]$rules.maximum_sources_per_cycle -gt 12) { throw 'Agency source-count boundary is invalid.' }
    if ([int]$rules.maximum_depth -lt 0 -or [int]$rules.maximum_depth -gt 4) { throw 'Agency maximum depth exceeds four.' }
    if ([int]$rules.maximum_files_per_source -lt 1 -or [int]$rules.maximum_files_per_source -gt 25000) { throw 'Agency per-source file cap is invalid.' }

    $expectedCrew = @('agency_director','data_cartographer','memory_librarian','workflow_operator','proof_auditor')
    $actualCrew = @($policy.crew | ForEach-Object { [string]$_.id })
    if (($actualCrew -join '|') -cne ($expectedCrew -join '|')) { throw 'Agency crew lanes changed or are incomplete.' }
    foreach ($member in @($policy.crew)) {
        if ([bool]$member.may_write_source_data) { throw "Agency crew member '$($member.id)' gained source-data write authority." }
        if ([bool]$member.may_approve) { throw "Agency crew member '$($member.id)' gained approval authority." }
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (@($policy.sources).Count -gt [int]$rules.maximum_sources_per_cycle) { throw 'Agency policy exceeds its source-count boundary.' }
    foreach ($source in @($policy.sources)) {
        $id = [string]$source.id
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw 'Agency source identifiers must be present and unique.' }
        if ([string]$source.base -notin @('project_root','user_profile')) { throw "Agency source '$id' has an unsupported base." }
        if (-not (Test-Arko95AgencyRelativePath -Path ([string]$source.relative_path))) { throw "Agency source '$id' escaped its declared base." }
        if ([string]$source.base -eq 'user_profile' -and ([string]::IsNullOrWhiteSpace([string]$source.relative_path) -or [string]$source.relative_path -eq '.')) { throw "Agency source '$id' cannot register the full user profile." }
        if ([int]$source.maximum_depth -lt 0 -or [int]$source.maximum_depth -gt [int]$rules.maximum_depth) { throw "Agency source '$id' exceeds the depth boundary." }
        if ([int]$source.maximum_files -lt 1 -or [int]$source.maximum_files -gt [int]$rules.maximum_files_per_source) { throw "Agency source '$id' exceeds the file boundary." }
        foreach ($exclude in @($source.excludes)) {
            if (-not (Test-Arko95AgencyRelativePath -Path ([string]$exclude))) { throw "Agency source '$id' has an unsafe exclusion." }
        }
    }
    $configuredForbidden = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($forbidden in @($policy.forbidden_user_profile_roots)) {
        if (-not (Test-Arko95AgencyRelativePath -Path ([string]$forbidden))) { throw 'Agency forbidden-root policy contains an unsafe path.' }
        $null = $configuredForbidden.Add(([string]$forbidden).Replace('/','\').Trim('\'))
    }
    foreach ($requiredForbidden in @(Get-Arko95AgencyRequiredForbiddenRoots)) {
        if (-not $configuredForbidden.Contains($requiredForbidden)) { throw "Agency policy removed required forbidden root '$requiredForbidden'." }
    }
    $requiredDenials = @('read_file_contents','store_raw_paths_or_file_names','follow_reparse_points','move_rename_delete_or_overwrite_source_data','execute_catalog_content','infer_authority_from_discovered_data','scan_legal_case_roots','store_credentials_or_browser_profiles','send_sync_publish_or_upload','auto_promote_backlog_proposals')
    $configuredDenials = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($denial in @($policy.hard_denials)) { $null=$configuredDenials.Add([string]$denial) }
    foreach ($requiredDenial in $requiredDenials) {
        if (-not $configuredDenials.Contains($requiredDenial)) { throw "Agency policy removed hard denial '$requiredDenial'." }
    }
    return $policy
}

function Resolve-Arko95AgencyRoot {
    param([Parameter(Mandatory)][string]$ProjectRoot,[Parameter(Mandatory)]$Source)
    $baseRoot = if ([string]$Source.base -eq 'project_root') { [IO.Path]::GetFullPath($ProjectRoot) } else { [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile')) }
    $relative = [string]$Source.relative_path
    $candidate = if ($relative -eq '.') { $baseRoot } else { [IO.Path]::GetFullPath((Join-Path $baseRoot $relative)) }
    $prefix = $baseRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($candidate -cne $baseRoot -and -not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Agency source '$($Source.id)' escaped its base." }
    return $candidate
}

function Test-Arko95AgencyPathHasReparseAncestor {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Boundary)
    $candidate=[IO.Path]::GetFullPath($Path)
    $boundaryFull=[IO.Path]::GetFullPath($Boundary).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    while ($true) {
        if (-not (Test-Arko95AgencyPathWithin -Candidate $candidate -Root $boundaryFull)) { return $true }
        if (Test-Path -LiteralPath $candidate) {
            $item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        }
        if ($candidate -ieq $boundaryFull) { break }
        $parent=Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $candidate) { return $true }
        $candidate=$parent
    }
    return $false
}

function Get-Arko95AgencyForbiddenRoots {
    param([Parameter(Mandatory)]$Policy)
    $profile = [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile'))
    $allRoots = @($Policy.forbidden_user_profile_roots) + @(Get-Arko95AgencyRequiredForbiddenRoots)
    return @($allRoots | Sort-Object -Unique | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $profile ([string]$_))) })
}

function Test-Arko95AgencyPathWithin {
    param([Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Root)
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    return $candidateFull -ceq $rootFull -or $candidateFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Test-Arko95AgencyExcludedRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath,[string[]]$Excludes=@())
    $normalized = $RelativePath.Replace('/','\').TrimStart('\')
    foreach ($exclude in $Excludes) {
        $candidate = ([string]$exclude).Replace('/','\').Trim('\')
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($normalized -ieq $candidate -or $normalized.StartsWith($candidate + '\',[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-Arko95AgencyNumericSum {
    param([AllowEmptyCollection()][object[]]$Items,[Parameter(Mandatory)][string]$Property)
    $measure=@($Items) | Measure-Object -Property $Property -Sum
    if($null -eq $measure -or $null -eq $measure.Sum){ return [int64]0 }
    return [int64]$measure.Sum
}

function Get-Arko95AgencySourceSummary {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock
    )
    $root = Resolve-Arko95AgencyRoot -ProjectRoot $ProjectRoot -Source $Source
    $rootHash = Get-Arko95AgencyHash -Text $root.ToLowerInvariant()
    $forbiddenRoots = Get-Arko95AgencyForbiddenRoots -Policy $Policy
    $sourceBoundary = if ([string]$Source.base -eq 'project_root') { [IO.Path]::GetFullPath($ProjectRoot) } else { [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile')) }
    if (@($forbiddenRoots | Where-Object { Test-Arko95AgencyPathWithin -Candidate $root -Root $_ }).Count -gt 0) {
        return [pscustomobject][ordered]@{ source_id=[string]$Source.id; available=$false; denied=$true; truncated=$false; root_sha256=$rootHash; directory_count=0; file_count=0; logical_bytes=0; stale_file_count=0; extension_counts=@(); duplicate_candidate_group_count=0; duplicate_candidate_file_count=0; duplicate_candidates=@(); skipped_reparse_points=0; error_types=@('forbidden_root') }
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject][ordered]@{ source_id=[string]$Source.id; available=$false; denied=$false; truncated=$false; root_sha256=$rootHash; directory_count=0; file_count=0; logical_bytes=0; stale_file_count=0; extension_counts=@(); duplicate_candidate_group_count=0; duplicate_candidate_file_count=0; duplicate_candidates=@(); skipped_reparse_points=0; error_types=@('source_unavailable') }
    }
    if (Test-Arko95AgencyPathHasReparseAncestor -Path $root -Boundary $sourceBoundary) {
        return [pscustomobject][ordered]@{ source_id=[string]$Source.id; available=$false; denied=$true; truncated=$false; root_sha256=$rootHash; directory_count=0; file_count=0; logical_bytes=0; stale_file_count=0; extension_counts=@(); duplicate_candidate_group_count=0; duplicate_candidate_file_count=0; duplicate_candidates=@(); skipped_reparse_points=1; error_types=@('source_or_ancestor_reparse_point') }
    }
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return [pscustomobject][ordered]@{ source_id=[string]$Source.id; available=$false; denied=$true; truncated=$false; root_sha256=$rootHash; directory_count=0; file_count=0; logical_bytes=0; stale_file_count=0; extension_counts=@(); duplicate_candidate_group_count=0; duplicate_candidate_file_count=0; duplicate_candidates=@(); skipped_reparse_points=1; error_types=@('source_root_reparse_point') }
    }

    $maxFiles = [int]$Source.maximum_files
    $maxDepth = [int]$Source.maximum_depth
    $deadlineSeconds = [double]$Policy.catalog_rules.maximum_runtime_seconds
    $staleBefore = [DateTimeOffset]::UtcNow.AddDays(-[int]$Policy.catalog_rules.stale_after_days)
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Path=$root; Depth=0 })
    $extensions = @{}
    $duplicateGroups = @{}
    $errorTypes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [int64]$logicalBytes = 0
    $fileCount = 0
    $directoryCount = 0
    $staleCount = 0
    $skippedReparse = 0
    $truncated = $false

    while ($queue.Count -gt 0) {
        if ($Clock.Elapsed.TotalSeconds -ge $deadlineSeconds -or $fileCount -ge $maxFiles) { $truncated=$true; break }
        $current = $queue.Dequeue()
        $enumerator = $null
        try {
            if (Test-Arko95AgencyPathHasReparseAncestor -Path $current.Path -Boundary $sourceBoundary) { $skippedReparse++; continue }
            $currentItem=Get-Item -LiteralPath $current.Path -Force -ErrorAction Stop
            if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skippedReparse++; continue }
            $directoryCount++
            $enumerator = [IO.Directory]::EnumerateFileSystemEntries([string]$current.Path).GetEnumerator()
            while ($enumerator.MoveNext()) {
                if ($Clock.Elapsed.TotalSeconds -ge $deadlineSeconds -or $fileCount -ge $maxFiles) { $truncated=$true; break }
                $full = [IO.Path]::GetFullPath([string]$enumerator.Current)
                $relative = [IO.Path]::GetRelativePath($root,$full)
                if (Test-Arko95AgencyExcludedRelativePath -RelativePath $relative -Excludes @($Source.excludes)) { continue }
                if (@($forbiddenRoots | Where-Object { Test-Arko95AgencyPathWithin -Candidate $full -Root $_ }).Count -gt 0) { continue }
                if (Test-Arko95AgencyPathHasReparseAncestor -Path $full -Boundary $sourceBoundary) { $skippedReparse++; continue }
                $child = Get-Item -LiteralPath $full -Force -ErrorAction Stop
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skippedReparse++; continue }
                if ($child.PSIsContainer) {
                    if ([int]$current.Depth -lt $maxDepth) { $queue.Enqueue([pscustomobject]@{ Path=$full; Depth=([int]$current.Depth + 1) }) }
                    continue
                }
                $fileCount++
                $length = [int64]$child.Length
                $logicalBytes += $length
                if (([DateTimeOffset]$child.LastWriteTimeUtc) -lt $staleBefore) { $staleCount++ }
                $extension = Get-Arko95AgencyExtensionBucket -Name ([string]$child.Name)
                if (-not $extensions.ContainsKey($extension)) { $extensions[$extension]=0 }
                $extensions[$extension] = [int]$extensions[$extension] + 1
                $duplicateKey = '{0}|{1}' -f $length,$extension
                if (-not $duplicateGroups.ContainsKey($duplicateKey)) { $duplicateGroups[$duplicateKey]=[pscustomobject]@{ logical_bytes=$length; extension=$extension; count=0 } }
                $duplicateGroups[$duplicateKey].count = [int]$duplicateGroups[$duplicateKey].count + 1
            }
        }
        catch { $null=$errorTypes.Add($_.Exception.GetType().Name) }
        finally { if ($null -ne $enumerator) { $enumerator.Dispose() } }
    }

    $extensionCounts = @($extensions.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First ([int]$Policy.catalog_rules.extension_limit) | ForEach-Object { [pscustomobject][ordered]@{ extension=[string]$_.Key; count=[int]$_.Value } })
    $duplicateCandidates = @($duplicateGroups.Values | Where-Object { [int]$_.count -gt 1 } | Sort-Object -Property @{Expression='count';Descending=$true},@{Expression='logical_bytes';Descending=$true} | Select-Object -First ([int]$Policy.catalog_rules.duplicate_candidate_limit) | ForEach-Object { [pscustomobject][ordered]@{ logical_bytes=[int64]$_.logical_bytes; extension=[string]$_.extension; count=[int]$_.count; interpretation='same_size_and_extension_only_not_content_verified' } })
    $duplicateFileCount = [int](Get-Arko95AgencyNumericSum -Items @($duplicateGroups.Values | Where-Object { [int]$_.count -gt 1 }) -Property 'count')
    [pscustomobject][ordered]@{
        source_id=[string]$Source.id
        available=$true
        denied=$false
        truncated=$truncated
        root_sha256=$rootHash
        directory_count=$directoryCount
        file_count=$fileCount
        logical_bytes=$logicalBytes
        stale_file_count=$staleCount
        extension_counts=$extensionCounts
        duplicate_candidate_group_count=@($duplicateGroups.Values | Where-Object { [int]$_.count -gt 1 }).Count
        duplicate_candidate_file_count=$duplicateFileCount
        duplicate_candidates=$duplicateCandidates
        skipped_reparse_points=$skippedReparse
        error_types=@($errorTypes | Sort-Object)
    }
}

function New-Arko95AgencyBacklog {
    param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Catalog)
    $items = [Collections.Generic.List[object]]::new()
    foreach ($source in @($Catalog.sources)) {
        $proposals = @()
        if (-not [bool]$source.available) { $proposals += [pscustomobject]@{ kind='verify_source_boundary'; priority=[int]$Policy.proposal_rules.unavailable_source_priority; reason='The allowlisted source was unavailable or denied.'; evidence='available=false' } }
        if ([bool]$source.truncated) { $proposals += [pscustomobject]@{ kind='narrow_source_boundary'; priority=[int]$Policy.proposal_rules.truncated_source_priority; reason='The source reached its runtime or file limit.'; evidence='truncated=true' } }
        if ([int]$source.duplicate_candidate_group_count -ge [int]$Policy.proposal_rules.minimum_duplicate_candidate_groups) { $proposals += [pscustomobject]@{ kind='review_duplicate_candidates'; priority=[int]$Policy.proposal_rules.duplicate_review_priority; reason='Same-size and extension groups warrant a separate content-hash preview.'; evidence=('candidate_groups=' + [int]$source.duplicate_candidate_group_count) } }
        if ([int]$source.stale_file_count -ge [int]$Policy.proposal_rules.minimum_stale_files) { $proposals += [pscustomobject]@{ kind='review_stale_inventory'; priority=[int]$Policy.proposal_rules.stale_review_priority; reason='The source contains a material stale-file population.'; evidence=('stale_files=' + [int]$source.stale_file_count) } }
        foreach ($proposal in $proposals) {
            $identity = '{0}|{1}|{2}' -f $Catalog.scan_id,[string]$source.source_id,[string]$proposal.kind
            $items.Add([pscustomobject][ordered]@{
                proposal_id='agency-proposal-' + (Get-Arko95AgencyHash -Text $identity).Substring(0,20)
                source_id=[string]$source.source_id
                kind=[string]$proposal.kind
                priority=[int]$proposal.priority
                reason=[string]$proposal.reason
                evidence=[string]$proposal.evidence
                effect='proposal_only'
                authority='none'
                requires_owner_approval=$true
                may_move_rename_delete=$false
                execution_capability=''
            })
        }
    }
    return @($items | Sort-Object priority,source_id,kind)
}

function Get-Arko95AgencyReplay {
    param([Parameter(Mandatory)]$Paths)
    $events = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    $previous = ''
    if (Test-Path -LiteralPath $Paths.Events -PathType Leaf) {
        $item = Get-Item -LiteralPath $Paths.Events -Force -ErrorAction Stop
        if ($item.Length -gt 8388608 -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Agency event ledger is unsafe or exceeds its size limit.' }
        foreach ($line in [IO.File]::ReadLines($Paths.Events)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $event = $line | Microsoft.PowerShell.Utility\ConvertFrom-Json -DateKind String -ErrorAction Stop }
            catch { $errors.Add('invalid_json'); break }
            $saved = [string]$event.event_hash
            $prior = [string]$event.previous_hash
            $event.PSObject.Properties.Remove('event_hash')
            $canonical = $event | ConvertTo-Json -Compress -Depth 24
            $computed = Get-Arko95AgencyHash -Text $canonical
            if ($prior -cne $previous) { $errors.Add('previous_hash_mismatch'); break }
            if ($saved -cne $computed) { $errors.Add('event_hash_mismatch'); break }
            $event | Add-Member -NotePropertyName event_hash -NotePropertyValue $saved
            $events.Add($event)
            $previous = $saved
        }
    }
    if (Test-Path -LiteralPath $Paths.ChainHead -PathType Leaf) {
        try {
            $head=Read-Arko95AgencyJson -Path $Paths.ChainHead -MaximumBytes 65536
            if ([int]$head.event_count -ne $events.Count) { $errors.Add('chain_head_count_mismatch') }
            if ([string]$head.head_hash -cne $previous) { $errors.Add('chain_head_hash_mismatch') }
        }
        catch { $errors.Add('chain_head_invalid') }
    }
    elseif ($events.Count -gt 0) { $errors.Add('chain_head_missing') }
    [pscustomobject]@{ Valid=($errors.Count -eq 0); Errors=$errors.ToArray(); Events=$events.ToArray(); EventCount=$events.Count; HeadHash=$previous }
}

function Add-Arko95AgencyEvent {
    param([Parameter(Mandatory)]$Paths,[Parameter(Mandatory)]$Catalog,[Parameter(Mandatory)][string]$CatalogHash,[Parameter(Mandatory)][string]$BacklogHash,[Parameter(Mandatory)][string]$PolicyHash)
    $replay = Get-Arko95AgencyReplay -Paths $Paths
    if (-not $replay.Valid) { throw 'Agency ledger failed verification before append.' }
    $event = [ordered]@{
        schema_version=1
        event_id='agency-event-' + [guid]::NewGuid().ToString('N')
        event_type='catalog_refreshed'
        recorded_at=[DateTimeOffset]::UtcNow.ToString('o')
        scan_id=[string]$Catalog.scan_id
        source_count=@($Catalog.sources).Count
        file_count=[int64]$Catalog.totals.file_count
        backlog_count=[int]$Catalog.backlog_count
        catalog_sha256=$CatalogHash
        backlog_sha256=$BacklogHash
        policy_sha256=$PolicyHash
        previous_hash=[string]$replay.HeadHash
    }
    $canonical = $event | ConvertTo-Json -Compress -Depth 24
    $event.event_hash = Get-Arko95AgencyHash -Text $canonical
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Paths.Events)) | Out-Null
    [IO.File]::AppendAllText($Paths.Events,(($event | ConvertTo-Json -Compress -Depth 24) + [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    Write-Arko95AgencyJsonAtomic -Path $Paths.ChainHead -Value ([ordered]@{ schema_version=1; event_count=($replay.EventCount + 1); head_hash=$event.event_hash; updated_at=$event.recorded_at })
    return [pscustomobject]$event
}

function Add-Arko95AgencyPrivacyMigrationEvent {
    param([Parameter(Mandatory)]$Paths,[Parameter(Mandatory)][string[]]$RemovedSnapshotHashes)
    $replay=Get-Arko95AgencyReplay -Paths $Paths
    if(-not $replay.Valid){ throw 'Agency ledger failed verification before privacy migration.' }
    $event=[ordered]@{
        schema_version=1
        event_id='agency-event-' + [guid]::NewGuid().ToString('N')
        event_type='privacy_migration_applied'
        recorded_at=[DateTimeOffset]::UtcNow.ToString('o')
        migration='fixed_extension_categories_v1'
        removed_snapshot_count=@($RemovedSnapshotHashes).Count
        removed_snapshot_sha256=@($RemovedSnapshotHashes|Sort-Object)
        source_data_changed=$false
        previous_hash=[string]$replay.HeadHash
    }
    $canonical=$event|ConvertTo-Json -Compress -Depth 24
    $event.event_hash=Get-Arko95AgencyHash -Text $canonical
    [IO.File]::AppendAllText($Paths.Events,(($event|ConvertTo-Json -Compress -Depth 24)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    Write-Arko95AgencyJsonAtomic -Path $Paths.ChainHead -Value ([ordered]@{schema_version=1;event_count=($replay.EventCount+1);head_hash=$event.event_hash;updated_at=$event.recorded_at})
    return [pscustomobject]$event
}

function Enter-Arko95AgencyMutex {
    param([Parameter(Mandatory)][string]$StateRoot)
    $digest = (Get-Arko95AgencyHash -Text ([IO.Path]::GetFullPath($StateRoot).ToLowerInvariant())).Substring(0,20)
    $mutex = [Threading.Mutex]::new($false,'Local\ARKO95-Agency-' + $digest)
    try { $acquired=$mutex.WaitOne([TimeSpan]::FromSeconds(10)) } catch [Threading.AbandonedMutexException] { $acquired=$true }
    if (-not $acquired) { $mutex.Dispose(); throw 'Agency catalog is busy in another process.' }
    return $mutex
}

function Exit-Arko95AgencyMutex {
    param([AllowNull()][Threading.Mutex]$Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

function Invoke-Arko95AgencyScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot)
    $paths = Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    $policy = Get-Arko95AgencyPolicy -ProjectRoot $ProjectRoot
    $mutex = Enter-Arko95AgencyMutex -StateRoot $paths.Root
    try {
        foreach ($directory in @($paths.Root,$paths.Snapshots)) {
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Agency state directory is a reparse point: $directory" }
        }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $summaries = [Collections.Generic.List[object]]::new()
        foreach ($source in @($policy.sources)) { $summaries.Add((Get-Arko95AgencySourceSummary -ProjectRoot $ProjectRoot -Policy $policy -Source $source -Clock $clock)) }
        $scanId = 'agency-scan-' + [guid]::NewGuid().ToString('N')
        $catalog = [pscustomobject][ordered]@{
            schema_version=1
            scan_id=$scanId
            generated_at=[DateTimeOffset]::UtcNow.ToString('o')
            mode='metadata_only'
            effect='proposal_only'
            authority='none'
            content_read=$false
            raw_paths_stored=$false
            content_hashes_computed=$false
            reparse_points_followed=$false
            elapsed_seconds=[math]::Round($clock.Elapsed.TotalSeconds,3)
            sources=$summaries.ToArray()
            totals=[pscustomobject][ordered]@{
                source_count=$summaries.Count
                available_source_count=@($summaries | Where-Object { $_.available }).Count
                truncated_source_count=@($summaries | Where-Object { $_.truncated }).Count
                directory_count=Get-Arko95AgencyNumericSum -Items $summaries.ToArray() -Property 'directory_count'
                file_count=Get-Arko95AgencyNumericSum -Items $summaries.ToArray() -Property 'file_count'
                logical_bytes=Get-Arko95AgencyNumericSum -Items $summaries.ToArray() -Property 'logical_bytes'
                stale_file_count=Get-Arko95AgencyNumericSum -Items $summaries.ToArray() -Property 'stale_file_count'
                duplicate_candidate_group_count=Get-Arko95AgencyNumericSum -Items $summaries.ToArray() -Property 'duplicate_candidate_group_count'
            }
            backlog_count=0
            limitations=@('No file contents were read.','Same-size and fixed extension-category groups are candidates, not proven duplicates.','The catalog is a local aggregate snapshot and may become stale.','Discovered data never grants execution authority.')
        }
        $backlogItems = New-Arko95AgencyBacklog -Policy $policy -Catalog $catalog
        $catalog.backlog_count=@($backlogItems).Count
        $backlog = [pscustomobject][ordered]@{ schema_version=1; scan_id=$scanId; generated_at=$catalog.generated_at; effect='proposal_only'; authority='none'; item_count=@($backlogItems).Count; items=@($backlogItems) }
        $snapshotPath = Join-Path $paths.Snapshots ($scanId + '.json')
        Write-Arko95AgencyJsonAtomic -Path $snapshotPath -Value $catalog
        Write-Arko95AgencyJsonAtomic -Path $paths.LatestCatalog -Value $catalog
        Write-Arko95AgencyJsonAtomic -Path $paths.LatestBacklog -Value $backlog
        $catalogHash=(Get-FileHash -LiteralPath $paths.LatestCatalog -Algorithm SHA256).Hash.ToLowerInvariant()
        $backlogHash=(Get-FileHash -LiteralPath $paths.LatestBacklog -Algorithm SHA256).Hash.ToLowerInvariant()
        $policyHash=(Get-FileHash -LiteralPath $paths.Policy -Algorithm SHA256).Hash.ToLowerInvariant()
        $event=Add-Arko95AgencyEvent -Paths $paths -Catalog $catalog -CatalogHash $catalogHash -BacklogHash $backlogHash -PolicyHash $policyHash
        [pscustomobject]@{ ScanId=$scanId; Catalog=$catalog; Backlog=$backlog; EventHash=$event.event_hash; Effect='proposal_only'; Authority='none' }
    }
    finally { Exit-Arko95AgencyMutex -Mutex $mutex }
}

function Test-Arko95AgencyChain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot)
    try {
        $paths=Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        $replay=Get-Arko95AgencyReplay -Paths $paths
        $errors=[Collections.Generic.List[string]]::new()
        foreach($error in @($replay.Errors)){ $errors.Add([string]$error) }
        if($replay.Valid -and $replay.EventCount -gt 0){
            $catalogEvents=@($replay.Events|Where-Object{[string]$_.event_type -eq 'catalog_refreshed'})
            if($catalogEvents.Count -eq 0){ $errors.Add('catalog_event_missing') }
            else {
            $last=$catalogEvents[-1]
            if(-not (Test-Path -LiteralPath $paths.LatestCatalog -PathType Leaf)){ $errors.Add('latest_catalog_missing') }
            elseif((Get-FileHash -LiteralPath $paths.LatestCatalog -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$last.catalog_sha256){ $errors.Add('latest_catalog_hash_mismatch') }
            if(-not (Test-Path -LiteralPath $paths.LatestBacklog -PathType Leaf)){ $errors.Add('latest_backlog_missing') }
            elseif((Get-FileHash -LiteralPath $paths.LatestBacklog -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$last.backlog_sha256){ $errors.Add('latest_backlog_hash_mismatch') }
            if(-not (Test-Path -LiteralPath $paths.Policy -PathType Leaf)){ $errors.Add('agency_policy_missing') }
            elseif((Get-FileHash -LiteralPath $paths.Policy -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$last.policy_sha256){ $errors.Add('agency_policy_hash_mismatch') }
            }
        }
        [pscustomobject]@{ Valid=($errors.Count -eq 0); Errors=$errors.ToArray(); EventCount=$replay.EventCount; HeadHash=$replay.HeadHash; Limitation='SHA-256 chaining and a local head detect ordinary edits and clean truncation but are not externally anchored against a same-user full rewrite.' }
    }
    catch { [pscustomobject]@{ Valid=$false; Errors=@($_.Exception.Message); EventCount=0; HeadHash=''; Limitation='Verification failed closed.' } }
}

function Invoke-Arko95AgencyPrivacyMigration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot,[Parameter(Mandatory)][switch]$AcknowledgeGeneratedSnapshotRemoval)
    if(-not $AcknowledgeGeneratedSnapshotRemoval){ throw 'Privacy migration requires explicit acknowledgement of generated snapshot removal.' }
    $paths=Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    $null=Get-Arko95AgencyPolicy -ProjectRoot $ProjectRoot
    $mutex=Enter-Arko95AgencyMutex -StateRoot $paths.Root
    try {
        $chain=Test-Arko95AgencyChain -ProjectRoot $ProjectRoot -StateRoot $StateRoot
        if(-not $chain.Valid){ throw 'Agency chain failed before privacy migration.' }
        $latest=Read-Arko95AgencyJson -Path $paths.LatestCatalog
        $currentScanId=if($null -eq $latest){''}else{[string]$latest.scan_id}
        $allowedBuckets=@('[none]','[code]','[document]','[structured]','[media]','[archive]','[binary]','[other]')
        $removedHashes=[Collections.Generic.List[string]]::new()
        foreach($file in @(Get-ChildItem -LiteralPath $paths.Snapshots -Filter 'agency-scan-*.json' -File -ErrorAction SilentlyContinue)){
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw 'Agency snapshot privacy migration encountered a reparse point.' }
            $snapshot=Read-Arko95AgencyJson -Path $file.FullName -MaximumBytes 8388608
            if($null -eq $snapshot -or [string]$snapshot.scan_id -eq $currentScanId){ continue }
            $labels=@(
                @($snapshot.sources|ForEach-Object{@($_.extension_counts)|ForEach-Object{[string]$_.extension}})
                @($snapshot.sources|ForEach-Object{@($_.duplicate_candidates)|ForEach-Object{[string]$_.extension}})
            )
            if(@($labels|Where-Object{$_ -notin $allowedBuckets}).Count -eq 0){ continue }
            if(-not (Test-Arko95AgencyPathWithin -Candidate $file.FullName -Root $paths.Snapshots)){ throw 'Agency snapshot escaped the privacy-migration boundary.' }
            $removedHashes.Add((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
            [IO.File]::Delete($file.FullName)
        }
        $event=$null
        if($removedHashes.Count -gt 0){ $event=Add-Arko95AgencyPrivacyMigrationEvent -Paths $paths -RemovedSnapshotHashes $removedHashes.ToArray() }
        return [pscustomobject]@{Migration='fixed_extension_categories_v1';RemovedSnapshotCount=$removedHashes.Count;RemovedSnapshotHashes=$removedHashes.ToArray();EventHash=if($null -eq $event){''}else{[string]$event.event_hash};SourceDataChanged=$false}
    }
    finally{ Exit-Arko95AgencyMutex -Mutex $mutex }
}

function Get-Arko95AgencyBacklog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot)
    $paths=Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    $backlog=Read-Arko95AgencyJson -Path $paths.LatestBacklog
    if ($null -eq $backlog) { return @() }
    return @($backlog.items)
}

function Get-Arko95AgencyStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot,[string]$StateRoot)
    $paths=Get-Arko95AgencyPaths -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    $policy=Get-Arko95AgencyPolicy -ProjectRoot $ProjectRoot
    $chain=Test-Arko95AgencyChain -ProjectRoot $ProjectRoot -StateRoot $StateRoot
    $catalog=Read-Arko95AgencyJson -Path $paths.LatestCatalog
    $backlog=Read-Arko95AgencyJson -Path $paths.LatestBacklog
    [pscustomobject]@{
        Initialized=($null -ne $catalog)
        Mode='metadata_only'
        Effect='proposal_only'
        Authority='none'
        ContentRead=$false
        RawPathsStored=$false
        SourceCount=@($policy.sources).Count
        CrewCount=@($policy.crew).Count
        ChainValid=[bool]$chain.Valid
        ChainErrors=@($chain.Errors)
        EventCount=[int]$chain.EventCount
        HeadHash=[string]$chain.HeadHash
        LastScanId=if($null -eq $catalog){''}else{[string]$catalog.scan_id}
        LastScanAt=if($null -eq $catalog){''}else{[string]$catalog.generated_at}
        TotalFiles=if($null -eq $catalog){0}else{[int64]$catalog.totals.file_count}
        TotalBytes=if($null -eq $catalog){0}else{[int64]$catalog.totals.logical_bytes}
        BacklogCount=if($null -eq $backlog){0}else{[int]$backlog.item_count}
    }
}

Export-ModuleMember -Function Get-Arko95AgencyPaths, Get-Arko95AgencyPolicy, Invoke-Arko95AgencyScan, Invoke-Arko95AgencyPrivacyMigration, Test-Arko95AgencyChain, Get-Arko95AgencyBacklog, Get-Arko95AgencyStatus
