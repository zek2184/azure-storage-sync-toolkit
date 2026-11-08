function Compare-AzStorageSyncInventory {
    <#
    .SYNOPSIS
    Compares two complete inventories one bucket at a time.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PreviousInventoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CurrentInventoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputPath
    )

    $previousManifest = Get-InventoryManifest -InventoryPath $PreviousInventoryPath
    $currentManifest = Get-InventoryManifest -InventoryPath $CurrentInventoryPath
    if ([int]$previousManifest.BucketCount -ne [int]$currentManifest.BucketCount) {
        throw 'Inventories must use the same BucketCount.'
    }

    $previousFullPath = Get-CanonicalToolkitPath -Path $PreviousInventoryPath
    $currentFullPath = Get-CanonicalToolkitPath -Path $CurrentInventoryPath
    $outputFullPath = Get-CanonicalToolkitPath -Path $OutputPath
    if ((Test-ToolkitPathWithinRoot -CandidatePath $outputFullPath -RootPath $previousFullPath) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $outputFullPath -RootPath $currentFullPath)) {
        throw 'OutputPath must not be inside either inventory path.'
    }
    if (Test-Path -LiteralPath $outputFullPath) {
        throw 'OutputPath already exists. Use a new path to preserve prior evidence.'
    }
    if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Create incremental comparison evidence')) {
        return
    }
    [void](New-Item -ItemType Directory -Path $outputFullPath -Force)

    $newWriter = Get-ToolkitUtf8Writer -Path (Join-Path $outputFullPath 'new.tsv')
    $modifiedWriter = Get-ToolkitUtf8Writer -Path (Join-Path $outputFullPath 'modified.tsv')
    $missingWriter = Get-ToolkitUtf8Writer -Path (Join-Path $outputFullPath 'missing-candidates.tsv')
    $newWriter.WriteLine("PathToken`tLength`tLastWriteTimeUtcTicks`tAttributes")
    $modifiedWriter.WriteLine("PathToken`tPreviousLength`tLength`tPreviousLastWriteTimeUtcTicks`tLastWriteTimeUtcTicks`tAttributes")
    $missingWriter.WriteLine("PathToken`tPreviousLength`tPreviousLastWriteTimeUtcTicks`tPreviousAttributes")
    [int64]$newCount = 0
    [int64]$modifiedCount = 0
    [int64]$missingCount = 0
    [int64]$unchangedCount = 0
    $startedUtc = [DateTime]::UtcNow
    $bucketCount = [int]$currentManifest.BucketCount

    try {
        for ($bucket = 0; $bucket -lt $bucketCount; $bucket++) {
            $bucketName = 'bucket-{0:D4}.tsv' -f $bucket
            $previous = Read-InventoryBucket -Path (Join-Path (Join-Path $PreviousInventoryPath 'buckets') $bucketName)
            $current = Read-InventoryBucket -Path (Join-Path (Join-Path $CurrentInventoryPath 'buckets') $bucketName)
            foreach ($relativePath in @($current.Keys)) {
                $currentRecord = $current[$relativePath]
                if (-not $previous.ContainsKey($relativePath)) {
                    $newWriter.WriteLine(("{0}`t{1}`t{2}`t{3}" -f $currentRecord.PathToken, $currentRecord.Length, $currentRecord.LastWriteTimeUtcTicks, $currentRecord.Attributes))
                    $newCount++
                    continue
                }

                $previousRecord = $previous[$relativePath]
                if ($currentRecord.Length -ne $previousRecord.Length -or
                    $currentRecord.LastWriteTimeUtcTicks -ne $previousRecord.LastWriteTimeUtcTicks) {
                    $modifiedWriter.WriteLine(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f
                        $currentRecord.PathToken, $previousRecord.Length, $currentRecord.Length,
                        $previousRecord.LastWriteTimeUtcTicks, $currentRecord.LastWriteTimeUtcTicks,
                        $currentRecord.Attributes))
                    $modifiedCount++
                }
                else { $unchangedCount++ }
                [void]$previous.Remove($relativePath)
            }

            foreach ($relativePath in @($previous.Keys)) {
                $previousRecord = $previous[$relativePath]
                $missingWriter.WriteLine(("{0}`t{1}`t{2}`t{3}" -f $previousRecord.PathToken, $previousRecord.Length, $previousRecord.LastWriteTimeUtcTicks, $previousRecord.Attributes))
                $missingCount++
            }
        }
    }
    finally {
        $newWriter.Dispose()
        $modifiedWriter.Dispose()
        $missingWriter.Dispose()
    }

    $manifest = [ordered]@{
        SchemaVersion = '1.0'
        DeltaId = [Guid]::NewGuid().ToString('D')
        ToolkitVersion = $script:ToolkitVersion
        Complete = $true
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        DurationMilliseconds = [int64]([DateTime]::UtcNow - $startedUtc).TotalMilliseconds
        PreviousInventoryId = [string]$previousManifest.InventoryId
        CurrentInventoryId = [string]$currentManifest.InventoryId
        BucketCount = $bucketCount
        NewCount = $newCount
        ModifiedCount = $modifiedCount
        MissingCandidateCount = $missingCount
        UnchangedCount = $unchangedCount
        MissingCandidateAction = 'None'
    }
    Write-ToolkitJson -Path (Join-Path $outputFullPath 'manifest.json') -Value $manifest

    return [pscustomobject]@{
        DeltaId = $manifest.DeltaId
        OutputPath = $outputFullPath
        NewCount = $newCount
        ModifiedCount = $modifiedCount
        MissingCandidateCount = $missingCount
        UnchangedCount = $unchangedCount
    }
}
