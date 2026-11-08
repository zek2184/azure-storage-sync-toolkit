function Get-ToolkitUtf8Writer {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    return New-Object System.IO.StreamWriter($Path, $false, $encoding)
}
function ConvertTo-InventoryPathToken {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RelativePath))
}

function ConvertFrom-InventoryPathToken {
    param([Parameter(Mandatory = $true)][string]$Token)

    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Token))
}

function Get-InventoryBucketIndex {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateRange(1, 4096)][int]$BucketCount
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($RelativePath.ToUpperInvariant())
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    return [int]([BitConverter]::ToUInt32($digest, 0) % [uint32]$BucketCount)
}

function Write-ToolkitJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-ToolkitJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file was not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    return $FullPath.Substring($RootPath.Length).TrimStart('\', '/').Replace('/', '\')
}

function Get-CanonicalToolkitPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -le $pathRoot.Length) {
        return $pathRoot
    }
    return $fullPath.TrimEnd('\', '/')
}

function Test-ToolkitPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $candidate = Get-CanonicalToolkitPath -Path $CandidatePath
    $root = Get-CanonicalToolkitPath -Path $RootPath
    if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-RedactedErrorMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    return $Message.Replace($SourceRoot, '[SOURCE]').Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
}
