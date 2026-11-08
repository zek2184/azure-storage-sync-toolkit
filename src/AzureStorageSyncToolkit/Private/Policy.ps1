function Get-NormalizedPreviewPolicy {
    param([hashtable]$Policy)

    $blockedExtensions = @()
    $reviewExtensions = @('.partial', '.pst', '.zip')
    [int64]$maxFileSizeBytes = 268435456000
    [int]$maxRelativePathLength = 1024
    [bool]$reviewZeroByteFiles = $true
    [bool]$reviewSystemFiles = $true

    if ($null -ne $Policy) {
        if ($Policy.ContainsKey('BlockedExtensions')) { $blockedExtensions = @($Policy.BlockedExtensions) }
        if ($Policy.ContainsKey('ReviewExtensions')) { $reviewExtensions = @($Policy.ReviewExtensions) }
        if ($Policy.ContainsKey('MaxFileSizeBytes')) { $maxFileSizeBytes = [int64]$Policy.MaxFileSizeBytes }
        if ($Policy.ContainsKey('MaxRelativePathLength')) { $maxRelativePathLength = [int]$Policy.MaxRelativePathLength }
        if ($Policy.ContainsKey('ReviewZeroByteFiles')) { $reviewZeroByteFiles = [bool]$Policy.ReviewZeroByteFiles }
        if ($Policy.ContainsKey('ReviewSystemFiles')) { $reviewSystemFiles = [bool]$Policy.ReviewSystemFiles }
    }

    if ($maxFileSizeBytes -lt 1) { throw 'MaxFileSizeBytes must be greater than zero.' }
    if ($maxRelativePathLength -lt 1) { throw 'MaxRelativePathLength must be greater than zero.' }

    $normalizeExtensions = {
        param([object[]]$Extensions)
        return @($Extensions | ForEach-Object {
            $value = ([string]$_).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($value)) { return }
            if (-not $value.StartsWith('.')) { $value = '.' + $value }
            $value
        } | Sort-Object -Unique)
    }

    return [ordered]@{
        BlockedExtensions = @(& $normalizeExtensions $blockedExtensions)
        ReviewExtensions = @(& $normalizeExtensions $reviewExtensions)
        MaxFileSizeBytes = $maxFileSizeBytes
        MaxRelativePathLength = $maxRelativePathLength
        ReviewZeroByteFiles = $reviewZeroByteFiles
        ReviewSystemFiles = $reviewSystemFiles
    }
}

function Get-PreviewPolicyDecision {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][int64]$Length,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Policy
    )

    $blockedIssues = New-Object System.Collections.Generic.List[string]
    $reviewIssues = New-Object System.Collections.Generic.List[string]
    $extension = [IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    $fileName = [IO.Path]::GetFileName($RelativePath).ToLowerInvariant()

    if (@($Policy.BlockedExtensions) -contains $extension) { $blockedIssues.Add('BLOCKED_EXTENSION') }
    if (@($Policy.ReviewExtensions) -contains $extension) { $reviewIssues.Add('REVIEW_EXTENSION') }
    if ($Length -gt [int64]$Policy.MaxFileSizeBytes) { $blockedIssues.Add('FILE_TOO_LARGE') }
    if ($RelativePath.Length -gt [int]$Policy.MaxRelativePathLength) { $blockedIssues.Add('PATH_TOO_LONG') }
    if ([bool]$Policy.ReviewZeroByteFiles -and $Length -eq 0) { $reviewIssues.Add('ZERO_BYTE_FILE') }
    if ([bool]$Policy.ReviewSystemFiles -and
        ($fileName -eq 'desktop.ini' -or $fileName -eq 'thumbs.db' -or
         $fileName -eq '.ds_store' -or $fileName.StartsWith('~$'))) {
        $reviewIssues.Add('SYSTEM_OR_TEMPORARY_FILE')
    }

    if ($blockedIssues.Count -gt 0) {
        return [pscustomobject]@{
            Decision = 'Blocked'
            Eligible = $false
            IssueCodes = (@($blockedIssues) + @($reviewIssues) | Sort-Object -Unique) -join ';'
        }
    }
    if ($reviewIssues.Count -gt 0) {
        return [pscustomobject]@{
            Decision = 'Review'
            Eligible = $false
            IssueCodes = (@($reviewIssues) | Sort-Object -Unique) -join ';'
        }
    }
    return [pscustomobject]@{
        Decision = 'Ready'
        Eligible = $true
        IssueCodes = ''
    }
}
