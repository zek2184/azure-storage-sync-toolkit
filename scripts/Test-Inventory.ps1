[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repositoryRoot 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncCompatibility-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$baseline = Join-Path $root 'baseline'
$current = Join-Path $root 'current'
$delta = Join-Path $root 'delta'
[void](New-Item -ItemType Directory -Path $source -Force)

try {
    [IO.File]::WriteAllText((Join-Path $source 'unchanged.txt'), 'same')
    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
    [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'remove')
    $first = New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8
    if ($first.FileCount -ne 3) { throw "Expected 3 baseline files, found $($first.FileCount)." }

    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after with a different length')
    Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
    [IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)
    $result = Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta

    if ($result.NewCount -ne 1 -or $result.ModifiedCount -ne 1 -or
        $result.MissingCandidateCount -ne 1 -or $result.UnchangedCount -ne 1) {
        throw "Unexpected delta: new=$($result.NewCount), modified=$($result.ModifiedCount), missing=$($result.MissingCandidateCount), unchanged=$($result.UnchangedCount)."
    }
    Write-Output 'PASS: disk-backed inventory and incremental comparison.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
