[CmdletBinding()]
param(
    [ValidateSet('Status','VerifyChain','NewCycle','AddRecord','ReviewLesson','CloseCycle')]
    [string]$Action = 'Status',
    [string]$ProjectRoot,
    [string]$CycleId,
    [string]$MissionId,
    [string]$ObjectiveHash,
    [int]$ExpectedVersion,
    [ValidateSet('observation','inference','projection','decision_proposal','outcome','lesson_candidate')]
    [string]$Kind = 'observation',
    [string]$Content,
    [string]$ProducerId = 'local_owner',
    [string[]]$ParentRecordIds = @(),
    [string]$SourceReference = '',
    [string]$AdapterId = '',
    [ValidateRange(0,100)][int]$Confidence = 50,
    [string]$Uncertainty = 'not_stated',
    [ValidateRange(1,25)][int]$CreditCost = 1,
    [string[]]$EvidenceSha256 = @(),
    [string]$SuggestedOperationsCapability = '',
    [string]$CandidateRecordId,
    [ValidateSet('owner_approved_reference','rejected')]
    [string]$ReviewState = 'rejected',
    [string]$Reason = 'owner_reviewed',
    [int]$TotalCredits = 100,
    [string]$StateRoot,
    [string]$MissionStateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
Import-Module (Join-Path $ProjectRoot 'shell\Arko95.DecisionLearning.psm1') -Force

switch ($Action) {
    'Status' {
        Get-Arko95DecisionLearningStatus -ProjectRoot $ProjectRoot -StateRoot $StateRoot | ConvertTo-Json -Depth 40
    }
    'VerifyChain' {
        Test-Arko95DecisionLearningChain -ProjectRoot $ProjectRoot -StateRoot $StateRoot | ConvertTo-Json -Depth 12
    }
    'NewCycle' {
        if ([string]::IsNullOrWhiteSpace($MissionId) -or [string]::IsNullOrWhiteSpace($ObjectiveHash)) { throw 'NewCycle requires -MissionId and -ObjectiveHash.' }
        New-Arko95DecisionCycle -ProjectRoot $ProjectRoot -MissionId $MissionId -ObjectiveHash $ObjectiveHash -TotalCredits $TotalCredits -ActorId $ProducerId -StateRoot $StateRoot -MissionStateRoot $MissionStateRoot | ConvertTo-Json -Depth 12
    }
    'AddRecord' {
        if ([string]::IsNullOrWhiteSpace($CycleId) -or $ExpectedVersion -lt 1 -or [string]::IsNullOrWhiteSpace($Content)) { throw 'AddRecord requires -CycleId, -ExpectedVersion, and -Content.' }
        Add-Arko95DecisionRecord -ProjectRoot $ProjectRoot -CycleId $CycleId -ExpectedVersion $ExpectedVersion -Kind $Kind -Content $Content -ProducerId $ProducerId -ParentRecordIds $ParentRecordIds -SourceReference $SourceReference -AdapterId $AdapterId -Confidence $Confidence -Uncertainty $Uncertainty -CreditCost $CreditCost -EvidenceSha256 $EvidenceSha256 -SuggestedOperationsCapability $SuggestedOperationsCapability -StateRoot $StateRoot -MissionStateRoot $MissionStateRoot | ConvertTo-Json -Depth 12
    }
    'ReviewLesson' {
        if ([string]::IsNullOrWhiteSpace($CycleId) -or $ExpectedVersion -lt 1 -or [string]::IsNullOrWhiteSpace($CandidateRecordId)) { throw 'ReviewLesson requires -CycleId, -ExpectedVersion, and -CandidateRecordId.' }
        Set-Arko95LessonCandidateReview -ProjectRoot $ProjectRoot -CycleId $CycleId -ExpectedVersion $ExpectedVersion -CandidateRecordId $CandidateRecordId -ReviewState $ReviewState -OwnerId $ProducerId -Reason $Reason -StateRoot $StateRoot -MissionStateRoot $MissionStateRoot | ConvertTo-Json -Depth 12
    }
    'CloseCycle' {
        if ([string]::IsNullOrWhiteSpace($CycleId) -or $ExpectedVersion -lt 1) { throw 'CloseCycle requires -CycleId and -ExpectedVersion.' }
        Close-Arko95DecisionCycle -ProjectRoot $ProjectRoot -CycleId $CycleId -ExpectedVersion $ExpectedVersion -ParentIntegratorId $ProducerId -StateRoot $StateRoot -MissionStateRoot $MissionStateRoot | ConvertTo-Json -Depth 12
    }
}
