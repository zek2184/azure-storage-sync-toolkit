[CmdletBinding()]
param(
    [ValidateRange(1000, 1000000)]
    [int]$RecordCount = 100000,

    [ValidateRange(1, 4096)]
    [int]$BucketCount = 256
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repositoryRoot 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncScale-' + [Guid]::NewGuid().ToString('N'))
$baseline = Join-Path $root 'baseline'
$current = Join-Path $root 'current'
$delta = Join-Path $root 'delta'
$bucketDirectory = Join-Path $baseline 'buckets'
[void](New-Item -ItemType Directory -Path $bucketDirectory -Force)
$writers = @{}
$encoding = New-Object System.Text.UTF8Encoding($false)
$baseTicks = [DateTime]::Parse('2026-01-01T00:00:00Z').Ticks

try {
    try {
        for ($index = 0; $index -lt $RecordCount; $index++) {
            $bucket = $index % $BucketCount
            if (-not $writers.ContainsKey($bucket)) {
                $bucketPath = Join-Path $bucketDirectory ('bucket-{0:D4}.tsv' -f $bucket)
                $writers[$bucket] = New-Object System.IO.StreamWriter($bucketPath, $false, $encoding)
            }
            $relativePath = 'Department-{0:D3}\File-{1:D7}.dat' -f ($index % 100), $index
            $pathToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($relativePath))
            $writers[$bucket].WriteLine(("{0}`t{1}`t{2}`t32" -f $pathToken, ($index % 4096), ($baseTicks + $index)))
        }
    }
    finally {
        foreach ($writer in $writers.Values) { $writer.Dispose() }
    }

    $baselineManifest = [ordered]@{
        SchemaVersion = '1.0'
        InventoryId = [Guid]::NewGuid().ToString('D')
        ToolkitVersion = Get-AzStorageSyncToolkitVersion
        Complete = $true
        SourceRoot = '[SOURCE]'
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        BucketCount = $BucketCount
        FileCount = $RecordCount
        FolderCount = 100
        TotalBytes = 0
        ScanErrorCount = 0
        PathEncoding = 'UTF8-Base64'
        ComparisonMetadata = @('Length', 'LastWriteTimeUtcTicks')
    }
    [IO.File]::WriteAllText(
        (Join-Path $baseline 'manifest.json'),
        ($baselineManifest | ConvertTo-Json -Depth 5),
        $encoding
    )

    Copy-Item -LiteralPath $baseline -Destination $current -Recurse
    $currentManifestPath = Join-Path $current 'manifest.json'
    $currentManifest = Get-Content -LiteralPath $currentManifestPath -Raw | ConvertFrom-Json
    $currentManifest.InventoryId = [Guid]::NewGuid().ToString('D')
    [IO.File]::WriteAllText($currentManifestPath, ($currentManifest | ConvertTo-Json -Depth 5), $encoding)

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $result = Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta
    $stopwatch.Stop()

    if ($result.UnchangedCount -ne $RecordCount -or $result.NewCount -ne 0 -or
        $result.ModifiedCount -ne 0 -or $result.MissingCandidateCount -ne 0) {
        throw "Scale comparison returned unexpected counts for $RecordCount records."
    }

    Write-Output ("PASS: compared {0:N0} synthetic records in {1:N2} seconds with bounded bucket loading." -f
        $RecordCount, $stopwatch.Elapsed.TotalSeconds)
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
