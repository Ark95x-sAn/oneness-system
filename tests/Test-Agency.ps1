[CmdletBinding()]
param([string]$ProjectRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ProjectRoot)){ $ProjectRoot=Split-Path -Parent $PSScriptRoot }
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$modulePath=Join-Path $ProjectRoot 'shell\Arko95.Agency.psm1'
$runnerPath=Join-Path $ProjectRoot 'scripts\Invoke-ARKO95Agency.ps1'
foreach($path in @($modulePath,$runnerPath)){
    $tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count -gt 0){ throw "PowerShell parse errors in ${path}: $($errors -join '; ')" }
}

Import-Module $modulePath -Force
$productionPolicy=Get-Arko95AgencyPolicy -ProjectRoot $ProjectRoot
if($productionPolicy.mode -ne 'metadata_only' -or $productionPolicy.default_effect -ne 'proposal_only' -or $productionPolicy.authority -ne 'none'){ throw 'Production agency policy gained authority or content access.' }
if(@($productionPolicy.sources).Count -gt 12 -or @($productionPolicy.crew).Count -ne 5){ throw 'Production agency source or crew boundary changed.' }
$forbiddenSourceFragments=@('rsb case','Downloads','.codex','AppData')
foreach($source in @($productionPolicy.sources)){
    foreach($fragment in $forbiddenSourceFragments){ if(([string]$source.relative_path).IndexOf($fragment,[StringComparison]::OrdinalIgnoreCase) -ge 0){ throw "Forbidden source fragment '$fragment' entered the production map." } }
}

$fixtureContainer=Join-Path (Join-Path $ProjectRoot 'state') ('test-agency-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot=Join-Path $fixtureContainer 'project'
$fixtureConfig=Join-Path $fixtureRoot 'config'
$fixtureData=Join-Path $fixtureRoot 'fixture-data'
$excludedData=Join-Path $fixtureData 'legal'
$junctionTarget=Join-Path $fixtureRoot 'junction-target'
$agencyState=Join-Path $fixtureRoot 'state\agency'

try{
    foreach($directory in @($fixtureConfig,$fixtureData,$excludedData,$junctionTarget)){ [IO.Directory]::CreateDirectory($directory)|Out-Null }
    $fixturePolicy=[ordered]@{
        schema_version=1;identity='ARKO-95 Agency Fixture';mode='metadata_only';default_effect='proposal_only';authority='none'
        catalog_rules=[ordered]@{maximum_runtime_seconds=20;maximum_sources_per_cycle=4;maximum_depth=3;maximum_files_per_source=100;path_storage='sha256_only';inspect_file_contents=$false;compute_content_hashes=$false;follow_reparse_points=$false;stale_after_days=1;extension_limit=8;duplicate_candidate_limit=8}
        crew=@(
            [ordered]@{id='agency_director';purpose='owner liaison';may_write_source_data=$false;may_approve=$false},
            [ordered]@{id='data_cartographer';purpose='map';may_write_source_data=$false;may_approve=$false},
            [ordered]@{id='memory_librarian';purpose='catalog';may_write_source_data=$false;may_approve=$false},
            [ordered]@{id='workflow_operator';purpose='backlog';may_write_source_data=$false;may_approve=$false},
            [ordered]@{id='proof_auditor';purpose='verify';may_write_source_data=$false;may_approve=$false}
        )
        sources=@(
            [ordered]@{id='fixture';base='project_root';relative_path='fixture-data';maximum_depth=2;maximum_files=100;excludes=@('legal')},
            [ordered]@{id='legal_probe';base='user_profile';relative_path='OneDrive\Desktop\rsb case';maximum_depth=1;maximum_files=10;excludes=@()}
        )
        forbidden_user_profile_roots=@('OneDrive\Desktop\rsb case','.ssh','.gnupg','.codex','Downloads','AppData','OneDrive\Personal Vault')
        proposal_rules=[ordered]@{minimum_stale_files=1;minimum_duplicate_candidate_groups=1;unavailable_source_priority=1;truncated_source_priority=2;duplicate_review_priority=3;stale_review_priority=4}
        hard_denials=@('read_file_contents','store_raw_paths_or_file_names','follow_reparse_points','move_rename_delete_or_overwrite_source_data','execute_catalog_content','infer_authority_from_discovered_data','scan_legal_case_roots','store_credentials_or_browser_profiles','send_sync_publish_or_upload','auto_promote_backlog_proposals')
    }
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($fixturePolicy|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $canary='SECRET_CONTENT_SHOULD_NEVER_ENTER_AGENCY_STATE'
    $fileA=Join-Path $fixtureData 'secret-password-a.txt'
    $fileB=Join-Path $fixtureData 'secret-password-b.txt'
    $fileC=Join-Path $fixtureData 'notes.log'
    $fileD=Join-Path $fixtureData 'record.SECRET_EXTENSION_TOKEN'
    $legalFile=Join-Path $excludedData 'excluded-legal-name.txt'
    [IO.File]::WriteAllText($fileA,$canary,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($fileB,$canary,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($fileC,'ordinary fixture content',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($fileD,'extension bucket fixture',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($legalFile,'LEGAL_CANARY_MUST_NOT_APPEAR',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $junctionTarget 'behind-junction.txt'),'JUNCTION_CANARY',[Text.UTF8Encoding]::new($false))
    [IO.File]::SetLastWriteTimeUtc($fileC,[DateTime]::UtcNow.AddDays(-10))
    $beforeHashes=@($fileA,$fileB,$fileC,$fileD,$legalFile|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash})
    $junctionCreated=$false
    try{ $null=New-Item -ItemType Junction -Path (Join-Path $fixtureData 'linked-data') -Target $junctionTarget -ErrorAction Stop;$junctionCreated=$true }catch{}

    $originalLocation=Get-Location
    try{
        $legalCwd='C:\Users\ArcXN\OneDrive\Desktop\rsb case\1_files'
        if(Test-Path -LiteralPath $legalCwd){ Set-Location -LiteralPath $legalCwd }
        $scan=Invoke-Arko95AgencyScan -ProjectRoot $fixtureRoot -StateRoot $agencyState
    }
    finally{ Set-Location -LiteralPath $originalLocation }

    if($scan.Effect -ne 'proposal_only' -or $scan.Authority -ne 'none'){ throw 'Agency scan gained authority.' }
    if($scan.Catalog.content_read -ne $false -or $scan.Catalog.raw_paths_stored -ne $false -or $scan.Catalog.content_hashes_computed -ne $false){ throw 'Agency scan crossed its metadata-only boundary.' }
    if($scan.Catalog.totals.file_count -ne 4){ throw "Agency scan counted excluded or reparse content: $($scan.Catalog.totals.file_count) files." }
    if($junctionCreated -and $scan.Catalog.sources[0].skipped_reparse_points -lt 1){ throw 'Agency scan did not record a skipped reparse point.' }
    $legalSummary=@($scan.Catalog.sources|Where-Object{$_.source_id -eq 'legal_probe'})[0]
    if($null -eq $legalSummary -or $legalSummary.available -or -not $legalSummary.denied -or 'forbidden_root' -notin @($legalSummary.error_types)){ throw 'The code-level legal-root boundary did not fail closed.' }
    $paths=Get-Arko95AgencyPaths -ProjectRoot $fixtureRoot -StateRoot $agencyState
    $catalogText=Get-Content -Raw -LiteralPath $paths.LatestCatalog
    $backlogText=Get-Content -Raw -LiteralPath $paths.LatestBacklog
    foreach($forbiddenText in @($canary,'LEGAL_CANARY_MUST_NOT_APPEAR','JUNCTION_CANARY','SECRET_EXTENSION_TOKEN','secret-password-a.txt','secret-password-b.txt','excluded-legal-name.txt','rsb case')){
        if($catalogText -match [regex]::Escape($forbiddenText) -or $backlogText -match [regex]::Escape($forbiddenText)){ throw "Agency state leaked forbidden text '$forbiddenText'." }
    }
    $afterHashes=@($fileA,$fileB,$fileC,$fileD,$legalFile|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash})
    if(($beforeHashes -join '|') -cne ($afterHashes -join '|')){ throw 'Agency scan modified source files.' }
    if($scan.Backlog.item_count -lt 2){ throw 'Agency did not compile duplicate and stale review proposals.' }
    if(@($scan.Backlog.items|Where-Object{$_.effect -ne 'proposal_only' -or $_.authority -ne 'none' -or $_.requires_owner_approval -ne $true -or $_.may_move_rename_delete -ne $false}).Count -ne 0){ throw 'Agency backlog gained control or destructive authority.' }
    $chain=Test-Arko95AgencyChain -ProjectRoot $fixtureRoot -StateRoot $agencyState
    if(-not $chain.Valid -or $chain.EventCount -ne 1){ throw 'Agency chain did not verify after the first scan.' }
    $status=Get-Arko95AgencyStatus -ProjectRoot $fixtureRoot -StateRoot $agencyState
    if(-not $status.Initialized -or -not $status.ChainValid -or $status.TotalFiles -ne 4 -or $status.BacklogCount -lt 2 -or $status.Authority -ne 'none'){ throw 'Agency status projection is inconsistent.' }
    $statusText=$status|ConvertTo-Json -Depth 24
    foreach($forbiddenText in @('rsb case','OneDrive\Desktop','C:\Users\ArcXN')){ if($statusText -match [regex]::Escape($forbiddenText)){ throw "Agency status leaked raw policy path '$forbiddenText'." } }

    $legacySnapshotPath=Join-Path $paths.Snapshots 'agency-scan-legacy.json'
    $legacySnapshot=[ordered]@{schema_version=1;scan_id='agency-scan-legacy';sources=@([ordered]@{extension_counts=@([ordered]@{extension='.SECRET_EXTENSION_TOKEN';count=1});duplicate_candidates=@()})}
    [IO.File]::WriteAllText($legacySnapshotPath,($legacySnapshot|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $migration=Invoke-Arko95AgencyPrivacyMigration -ProjectRoot $fixtureRoot -StateRoot $agencyState -AcknowledgeGeneratedSnapshotRemoval
    if($migration.RemovedSnapshotCount -ne 1 -or $migration.SourceDataChanged -ne $false -or (Test-Path -LiteralPath $legacySnapshotPath)){ throw 'Agency privacy migration did not remove only the legacy generated snapshot.' }
    $chainAfterMigration=Test-Arko95AgencyChain -ProjectRoot $fixtureRoot -StateRoot $agencyState
    if(-not $chainAfterMigration.Valid -or $chainAfterMigration.EventCount -ne 2){ throw 'Agency privacy migration did not preserve the receipt chain.' }

    $escapedPolicy=$fixturePolicy | ConvertTo-Json -Depth 24 | ConvertFrom-Json -DateKind String
    $escapedPolicy.sources[0].relative_path='..\outside'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($escapedPolicy|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $escapeBlocked=$false
    try{ Get-Arko95AgencyPolicy -ProjectRoot $fixtureRoot|Out-Null }catch{ $escapeBlocked=$true }
    if(-not $escapeBlocked){ throw 'Agency accepted a source path escape.' }
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($fixturePolicy|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))

    $removedLegalDenial=$fixturePolicy|ConvertTo-Json -Depth 24|ConvertFrom-Json -DateKind String
    $removedLegalDenial.forbidden_user_profile_roots=@($removedLegalDenial.forbidden_user_profile_roots|Where-Object{$_ -ne 'OneDrive\Desktop\rsb case'})
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($removedLegalDenial|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $legalDenialRemovalBlocked=$false
    try{ Get-Arko95AgencyPolicy -ProjectRoot $fixtureRoot|Out-Null }catch{ $legalDenialRemovalBlocked=$true }
    if(-not $legalDenialRemovalBlocked){ throw 'Agency accepted removal of the required legal-root denial.' }

    $crewApprovalPolicy=$fixturePolicy|ConvertTo-Json -Depth 24|ConvertFrom-Json -DateKind String
    $crewApprovalPolicy.crew[0].may_approve=$true
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($crewApprovalPolicy|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))
    $crewApprovalBlocked=$false
    try{ Get-Arko95AgencyPolicy -ProjectRoot $fixtureRoot|Out-Null }catch{ $crewApprovalBlocked=$true }
    if(-not $crewApprovalBlocked){ throw 'Agency accepted crew approval authority.' }
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'agency.json'),($fixturePolicy|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false))

    $null=Invoke-Arko95AgencyScan -ProjectRoot $fixtureRoot -StateRoot $agencyState
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in [IO.File]::ReadLines($paths.Events)){ $lines.Add($line) }
    $lines.RemoveAt($lines.Count-1)
    [IO.File]::WriteAllLines($paths.Events,$lines,[Text.UTF8Encoding]::new($false))
    $tamper=Test-Arko95AgencyChain -ProjectRoot $fixtureRoot -StateRoot $agencyState
    if($tamper.Valid -or 'chain_head_count_mismatch' -notin @($tamper.Errors)){ throw 'Agency chain did not detect clean tail truncation.' }

    [pscustomobject]@{
        ok=$true
        mode='metadata_only'
        production_source_count=@($productionPolicy.sources).Count
        fixture_files=$status.TotalFiles
        backlog_count=$status.BacklogCount
        content_read=$false
        raw_paths_stored=$false
        source_files_unchanged=$true
        legal_cwd_isolated=$true
        reparse_skip=$(if($junctionCreated){'verified'}else{'not_supported_on_host'})
        path_escape_rejection='verified'
        required_legal_denial='verified'
        extension_redaction='verified'
        legacy_snapshot_privacy_migration='verified'
        zero_crew_approval='verified'
        tail_truncation_detection='verified'
        authority='none'
    }|ConvertTo-Json -Depth 5
}
finally{
    $full=[IO.Path]::GetFullPath($fixtureContainer)
    $stateRoot=[IO.Path]::GetFullPath((Join-Path $ProjectRoot 'state')).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($stateRoot,[StringComparison]::OrdinalIgnoreCase)){ throw 'Refusing to remove an agency test path outside project state.' }
    if(Test-Path -LiteralPath $full){ Remove-Item -LiteralPath $full -Recurse -Force }
}
