[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repositoryRoot 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncApplyCompatibility-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$destination = Join-Path $root 'destination'
$state = Join-Path $root 'state'
$baseline = Join-Path $root 'baseline'
$current = Join-Path $root 'current'
$delta = Join-Path $root 'delta'
$plan = Join-Path $root 'plan'
[void](New-Item -ItemType Directory -Path $source, $destination -Force)

try {
    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
    [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'retain at destination')
    Copy-Item -LiteralPath (Join-Path $source 'modified.txt') -Destination $destination
    Copy-Item -LiteralPath (Join-Path $source 'missing.txt') -Destination $destination
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8)

    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after with a different length')
    Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
    [IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)
    [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta)
    $preview = New-AzStorageSyncPreviewPlan -DeltaPath $delta -CurrentInventoryPath $current -OutputPath $plan
    $first = Invoke-AzStorageSyncPlan -PlanPath $plan -DeltaPath $delta -CurrentInventoryPath $current `
        -SourcePath $source -DestinationPath $destination -StatePath $state `
        -ApprovedPlanId $preview.PlanId -Confirm:$false

    if ($first.CopiedCount -ne 2 -or -not (Test-Path -LiteralPath (Join-Path $destination 'missing.txt'))) {
        throw 'Successful apply did not copy the expected items or removed a missing candidate.'
    }

    [IO.File]::WriteAllText((Join-Path $source 'later-one.txt'), 'one')
    [IO.File]::WriteAllText((Join-Path $source 'later-two.txt'), 'two')
    $nextInventory = Join-Path $root 'next-inventory'
    $nextDelta = Join-Path $root 'next-delta'
    $nextPlan = Join-Path $root 'next-plan'
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $nextInventory -BucketCount 8)
    [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $first.BaselinePath -CurrentInventoryPath $nextInventory -OutputPath $nextDelta)
    $nextPreview = New-AzStorageSyncPreviewPlan -DeltaPath $nextDelta -CurrentInventoryPath $nextInventory -OutputPath $nextPlan
    $pointerBefore = Get-Content -LiteralPath (Join-Path $state 'current.json') -Raw | ConvertFrom-Json

    try {
        [void](Invoke-AzStorageSyncPlan -PlanPath $nextPlan -DeltaPath $nextDelta -CurrentInventoryPath $nextInventory `
            -SourcePath $source -DestinationPath $destination -StatePath $state `
            -ApprovedPlanId $nextPreview.PlanId -TestFailureAfter 1 -Confirm:$false)
        throw 'The injected failure did not occur.'
    }
    catch {
        if ($_.Exception.Message -eq 'The injected failure did not occur.') { throw }
    }

    $pointerAfterFailure = Get-Content -LiteralPath (Join-Path $state 'current.json') -Raw | ConvertFrom-Json
    if ($pointerAfterFailure.InventoryId -ne $pointerBefore.InventoryId) {
        throw 'A failed run replaced the successful baseline pointer.'
    }

    $retry = Invoke-AzStorageSyncPlan -PlanPath $nextPlan -DeltaPath $nextDelta -CurrentInventoryPath $nextInventory `
        -SourcePath $source -DestinationPath $destination -StatePath $state `
        -ApprovedPlanId $nextPreview.PlanId -Confirm:$false
    if (($retry.CopiedCount + $retry.AlreadyCurrentCount) -ne 2) { throw 'Retry did not reconcile both ready items.' }

    $noChangeInventory = Join-Path $root 'no-change-inventory'
    $noChangeDelta = Join-Path $root 'no-change-delta'
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $noChangeInventory -BucketCount 8)
    $noChange = Compare-AzStorageSyncInventory -PreviousInventoryPath $retry.BaselinePath -CurrentInventoryPath $noChangeInventory -OutputPath $noChangeDelta
    if ($noChange.NewCount -ne 0 -or $noChange.ModifiedCount -ne 0 -or $noChange.MissingCandidateCount -ne 0) {
        throw 'The unchanged rerun produced unexpected candidates.'
    }

    Write-Output 'PASS: approved apply, non-destructive missing candidates, failure recovery, retry, and no-op rerun.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
