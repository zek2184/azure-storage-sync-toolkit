function Get-PreviewPlanReadyRecord {
    param([Parameter(Mandatory = $true)][string]$PlanItemsPath)

    $reader = [IO.File]::OpenText($PlanItemsPath)
    try {
        [void]$reader.ReadLine()
        while ($null -ne ($line = $reader.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split([char]9)
            if ($parts.Count -ne 7) { throw 'The preview plan contains an invalid item record.' }
            if ($parts[4] -eq 'Ready' -and $parts[5] -eq 'true' -and
                $parts[1] -in @('New', 'Modified')) {
                [pscustomobject]@{
                    PathToken = $parts[0]
                    RelativePath = ConvertFrom-InventoryPathToken -Token $parts[0]
                    ChangeType = $parts[1]
                    Length = [int64]$parts[2]
                    LastWriteTimeUtcTicks = [int64]$parts[3]
                }
            }
        }
    }
    finally { $reader.Dispose() }
}

function Resolve-ToolkitRelativeFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'The plan contains an invalid relative path.'
    }
    foreach ($segment in $RelativePath.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($segment -eq '.' -or $segment -eq '..') { throw 'The plan contains a traversal path segment.' }
    }

    $root = Get-CanonicalToolkitPath -Path $RootPath
    $candidate = Get-CanonicalToolkitPath -Path (Join-Path $root $RelativePath)
    if (-not (Test-ToolkitPathWithinRoot -CandidatePath $candidate -RootPath $root) -or
        $candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The plan path resolves outside the configured root.'
    }
    return $candidate
}

function Assert-ToolkitSourceRecord {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][pscustomobject]$Record
    )

    $sourceFile = Resolve-ToolkitRelativeFilePath -RootPath $SourceRoot -RelativePath $Record.RelativePath
    $item = Get-Item -LiteralPath $sourceFile -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw "Planned source item is not a file: $($Record.RelativePath)" }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Planned source item is a reparse point: $($Record.RelativePath)"
    }
    if ([int64]$item.Length -ne [int64]$Record.Length -or
        [int64]$item.LastWriteTimeUtc.Ticks -ne [int64]$Record.LastWriteTimeUtcTicks) {
        throw "Planned source item changed after inventory: $($Record.RelativePath)"
    }
    return $sourceFile
}
