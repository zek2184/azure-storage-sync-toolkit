[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repositoryRoot 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncPreviewCompatibility-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$baseline = Join-Path $root 'baseline'
$current = Join-Path $root 'current'
$delta = Join-Path $root 'delta'
$plan = Join-Path $root 'plan'
[void](New-Item -ItemType Directory -Path $source -Force)

try {
    [IO.File]::WriteAllText((Join-Path $source 'stable.txt'), 'stable')
    [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'missing')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8)

    Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
    [IO.File]::WriteAllText((Join-Path $source 'ready.txt'), 'ready')
    [IO.File]::WriteAllText((Join-Path $source 'blocked.exe'), 'blocked')
    [IO.File]::WriteAllText((Join-Path $source 'review.pst'), 'review')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)
    [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta)

    $preview = New-AzStorageSyncPreviewPlan -DeltaPath $delta -CurrentInventoryPath $current -OutputPath $plan -Policy @{
        BlockedExtensions = @('.exe')
        ReviewExtensions = @('.pst')
    }
    if ($preview.ReadyCount -ne 1 -or $preview.ReviewCount -ne 1 -or
        $preview.BlockedCount -ne 1 -or $preview.EvidenceOnlyCount -ne 1) {
        throw 'Preview classifications did not match the expected synthetic scenario.'
    }

    $validation = Test-AzStorageSyncPreviewPlan -PlanPath $plan -DeltaPath $delta -CurrentInventoryPath $current
    if (-not $validation.IsValid) { throw "Preview validation failed: $($validation.Errors -join '; ')" }

    Add-Content -LiteralPath (Join-Path $plan 'plan-items.tsv') -Value 'tampered'
    $tampered = Test-AzStorageSyncPreviewPlan -PlanPath $plan -DeltaPath $delta -CurrentInventoryPath $current
    if ($tampered.IsValid) { throw 'Tampered plan items were accepted.' }

    Write-Output 'PASS: policy decisions, immutable fingerprints, tamper detection, and evidence-only missing candidates.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
