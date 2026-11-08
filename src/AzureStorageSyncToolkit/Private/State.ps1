function Write-ToolkitAtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $temporaryPath = Join-Path $parent ('.atomic-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-ToolkitJson -Path $temporaryPath -Value $Value
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backupPath = Join-Path $parent ('.previous-' + [Guid]::NewGuid().ToString('N') + '.bak')
            [IO.File]::Replace($temporaryPath, $Path, $backupPath)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Copy-ToolkitInventoryToState {
    param(
        [Parameter(Mandatory = $true)][string]$InventoryPath,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$InventoryId
    )

    $baselineRoot = Join-Path $StatePath 'baselines'
    [void](New-Item -ItemType Directory -Path $baselineRoot -Force)
    $finalPath = Join-Path $baselineRoot $InventoryId
    if (Test-Path -LiteralPath $finalPath -PathType Container) {
        $existing = Get-InventoryManifest -InventoryPath $finalPath
        if ([string]$existing.InventoryId -ne $InventoryId) {
            throw 'The existing state baseline has an unexpected inventory identifier.'
        }
        return $finalPath
    }

    $temporaryPath = Join-Path $baselineRoot ('.inprogress-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $temporaryPath -Force)
    try {
        foreach ($item in @(Get-ChildItem -LiteralPath $InventoryPath -Force)) {
            Copy-Item -LiteralPath $item.FullName -Destination $temporaryPath -Recurse -Force
        }
        $copied = Get-InventoryManifest -InventoryPath $temporaryPath
        if ([string]$copied.InventoryId -ne $InventoryId) {
            throw 'The copied state baseline failed inventory identity validation.'
        }
        [IO.Directory]::Move($temporaryPath, $finalPath)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Recurse -Force }
    }
    return $finalPath
}
