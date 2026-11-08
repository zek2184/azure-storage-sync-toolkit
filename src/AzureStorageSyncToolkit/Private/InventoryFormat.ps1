function Read-InventoryBucket {
    param([Parameter(Mandatory = $true)][string]$Path)

    $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $records
    }

    $reader = [IO.File]::OpenText($Path)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split([char]9)
            if ($parts.Count -ne 4) { throw "Invalid inventory record in $Path" }

            $relativePath = ConvertFrom-InventoryPathToken -Token $parts[0]
            $records[$relativePath] = [pscustomobject]@{
                RelativePath = $relativePath
                PathToken = $parts[0]
                Length = [int64]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
                LastWriteTimeUtcTicks = [int64]::Parse($parts[2], [Globalization.CultureInfo]::InvariantCulture)
                Attributes = [int]::Parse($parts[3], [Globalization.CultureInfo]::InvariantCulture)
            }
        }
    }
    finally {
        $reader.Dispose()
    }
    return $records
}
function Get-InventoryManifest {
    param([Parameter(Mandatory = $true)][string]$InventoryPath)

    $manifest = Read-ToolkitJson -Path (Join-Path $InventoryPath 'manifest.json')
    if ([string]$manifest.SchemaVersion -ne '1.0') {
        throw "Unsupported inventory schema version: $($manifest.SchemaVersion)"
    }
    if (-not [bool]$manifest.Complete) { throw 'The inventory is not marked complete.' }
    return $manifest
}
