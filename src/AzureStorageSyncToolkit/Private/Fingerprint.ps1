function Get-ToolkitSha256ForString {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
    }
    finally {
        $sha256.Dispose()
    }
    return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
}

function Get-ToolkitSha256ForFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required fingerprint file was not found: $Path"
    }
    $stream = [IO.File]::OpenRead($Path)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($stream)
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
    return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
}

function ConvertTo-ToolkitCsvField {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) { return '""' }
    $safeValue = $Value
    if ($safeValue -match '^[=+\-@]') {
        $safeValue = "'" + $safeValue
    }
    return '"' + $safeValue.Replace('"', '""') + '"'
}
