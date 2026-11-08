function New-AzStorageSyncInventory {
    <#
    .SYNOPSIS
    Creates a redacted, disk-backed inventory of a file source.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SourcePath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$InventoryPath,
        [ValidateRange(1, 4096)][int]$BucketCount = 256
    )

    $sourceItem = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
    if (-not $sourceItem.PSIsContainer) { throw 'SourcePath must identify a directory.' }

    $sourceRoot = Get-CanonicalToolkitPath -Path $sourceItem.FullName
    $inventoryFullPath = Get-CanonicalToolkitPath -Path $InventoryPath
    if (Test-ToolkitPathWithinRoot -CandidatePath $inventoryFullPath -RootPath $sourceRoot) {
        throw 'InventoryPath must not be inside SourcePath.'
    }
    if (Test-Path -LiteralPath $inventoryFullPath) {
        throw 'InventoryPath already exists. Use a new path to preserve prior evidence.'
    }
    if (-not $PSCmdlet.ShouldProcess($inventoryFullPath, 'Create disk-backed inventory')) {
        return
    }

    $bucketDirectory = Join-Path $inventoryFullPath 'buckets'
    [void](New-Item -ItemType Directory -Path $bucketDirectory -Force)
    $scanErrorWriter = Get-ToolkitUtf8Writer -Path (Join-Path $inventoryFullPath 'scan-errors.tsv')
    $scanErrorWriter.WriteLine("PathToken`tStage`tMessage")
    $writers = @{}
    $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
    $pendingDirectories.Push($sourceRoot)
    [int64]$fileCount = 0
    [int64]$folderCount = 0
    [int64]$totalBytes = 0
    [int64]$scanErrorCount = 0
    $startedUtc = [DateTime]::UtcNow

    try {
        while ($pendingDirectories.Count -gt 0) {
            $currentDirectory = $pendingDirectories.Pop()
            $folderCount++
            $directoryInfo = New-Object System.IO.DirectoryInfo($currentDirectory)
            try { $files = @($directoryInfo.GetFiles() | Sort-Object Name) }
            catch {
                $relativeDirectory = Get-NormalizedRelativePath -RootPath $sourceRoot -FullPath $currentDirectory
                $message = ConvertTo-RedactedErrorMessage -Message $_.Exception.Message -SourceRoot $sourceRoot
                $scanErrorWriter.WriteLine("$(ConvertTo-InventoryPathToken $relativeDirectory)`tFiles`t$message")
                $scanErrorCount++
                $files = @()
            }

            foreach ($file in $files) {
                try {
                    $relativePath = Get-NormalizedRelativePath -RootPath $sourceRoot -FullPath $file.FullName
                    $pathToken = ConvertTo-InventoryPathToken -RelativePath $relativePath
                    $bucket = Get-InventoryBucketIndex -RelativePath $relativePath -BucketCount $BucketCount
                    if (-not $writers.ContainsKey($bucket)) {
                        $writers[$bucket] = Get-ToolkitUtf8Writer -Path (Join-Path $bucketDirectory ('bucket-{0:D4}.tsv' -f $bucket))
                    }
                    $writers[$bucket].WriteLine(("{0}`t{1}`t{2}`t{3}" -f
                        $pathToken, $file.Length, $file.LastWriteTimeUtc.Ticks, ([int]$file.Attributes)))
                    $fileCount++
                    $totalBytes += [int64]$file.Length
                }
                catch {
                    $relativeFile = Get-NormalizedRelativePath -RootPath $sourceRoot -FullPath $file.FullName
                    $message = ConvertTo-RedactedErrorMessage -Message $_.Exception.Message -SourceRoot $sourceRoot
                    $scanErrorWriter.WriteLine("$(ConvertTo-InventoryPathToken $relativeFile)`tMetadata`t$message")
                    $scanErrorCount++
                }
            }

            try { $directories = @($directoryInfo.GetDirectories() | Sort-Object Name -Descending) }
            catch {
                $relativeDirectory = Get-NormalizedRelativePath -RootPath $sourceRoot -FullPath $currentDirectory
                $message = ConvertTo-RedactedErrorMessage -Message $_.Exception.Message -SourceRoot $sourceRoot
                $scanErrorWriter.WriteLine("$(ConvertTo-InventoryPathToken $relativeDirectory)`tDirectories`t$message")
                $scanErrorCount++
                $directories = @()
            }

            foreach ($directory in $directories) {
                if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $relativeDirectory = Get-NormalizedRelativePath -RootPath $sourceRoot -FullPath $directory.FullName
                    $scanErrorWriter.WriteLine("$(ConvertTo-InventoryPathToken $relativeDirectory)`tTraversal`tSkipped reparse point.")
                    $scanErrorCount++
                    continue
                }
                $pendingDirectories.Push($directory.FullName)
            }
        }
    }
    finally {
        foreach ($writer in $writers.Values) { $writer.Dispose() }
        $scanErrorWriter.Dispose()
    }

    $manifest = [ordered]@{
        SchemaVersion = '1.0'
        InventoryId = [Guid]::NewGuid().ToString('D')
        ToolkitVersion = $script:ToolkitVersion
        Complete = $true
        SourceRoot = '[SOURCE]'
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        DurationMilliseconds = [int64]([DateTime]::UtcNow - $startedUtc).TotalMilliseconds
        BucketCount = $BucketCount
        FileCount = $fileCount
        FolderCount = $folderCount
        TotalBytes = $totalBytes
        ScanErrorCount = $scanErrorCount
        PathEncoding = 'UTF8-Base64'
        ComparisonMetadata = @('Length', 'LastWriteTimeUtcTicks')
    }
    Write-ToolkitJson -Path (Join-Path $inventoryFullPath 'manifest.json') -Value $manifest

    return [pscustomobject]@{
        InventoryId = $manifest.InventoryId
        InventoryPath = $inventoryFullPath
        FileCount = $fileCount
        FolderCount = $folderCount
        TotalBytes = $totalBytes
        ScanErrorCount = $scanErrorCount
        BucketCount = $BucketCount
    }
}
