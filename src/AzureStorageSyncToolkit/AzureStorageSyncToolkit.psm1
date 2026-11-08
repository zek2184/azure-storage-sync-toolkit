Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ToolkitVersion = '0.1.0'
$script:RequiredConfigurationKeys = @(
    'SourcePath',
    'DestinationPath',
    'WorkingPath',
    'Provider'
)
$script:ProhibitedTransferOptions = @(
    '/MIR',
    '/PURGE',
    '/MOVE',
    '/MOV',
    '/COPYALL',
    '/SEC',
    '/SECFIX'
)

function Get-AzStorageSyncToolkitVersion {
    <#
    .SYNOPSIS
    Returns the toolkit module version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:ToolkitVersion
}

function Test-AzStorageSyncConfiguration {
    <#
    .SYNOPSIS
    Performs foundation-level schema and safety validation.

    .DESCRIPTION
    This pre-release validator checks required keys, supported provider values,
    distinct paths, and prohibited transfer options. It does not access the
    filesystem or prove that a migration can run.

    .PARAMETER Configuration
    Configuration hashtable to validate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable]$Configuration
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($key in $script:RequiredConfigurationKeys) {
        if (-not $Configuration.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string]$Configuration[$key])) {
            $errors.Add("Missing required configuration value: $key")
        }
    }

    if ($Configuration.ContainsKey('Provider') -and
        -not [string]::IsNullOrWhiteSpace([string]$Configuration.Provider) -and
        [string]$Configuration.Provider -ne 'FileSystem') {
        $errors.Add('Provider must be FileSystem in version 1.')
    }

    if ($Configuration.ContainsKey('SourcePath') -and
        $Configuration.ContainsKey('DestinationPath') -and
        -not [string]::IsNullOrWhiteSpace([string]$Configuration.SourcePath) -and
        [string]$Configuration.SourcePath -eq [string]$Configuration.DestinationPath) {
        $errors.Add('SourcePath and DestinationPath must be different.')
    }

    $options = @()
    if ($Configuration.ContainsKey('TransferOptions') -and $null -ne $Configuration.TransferOptions) {
        $options = @($Configuration.TransferOptions)
    }

    foreach ($option in $options) {
        $normalizedOption = ([string]$option).Trim().ToUpperInvariant()
        if ($script:ProhibitedTransferOptions -contains $normalizedOption) {
            $errors.Add("Prohibited transfer option: $normalizedOption")
        }
    }

    if ($options.Count -eq 0) {
        $warnings.Add('TransferOptions is empty; milestone 4 will define safe defaults.')
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
        Warnings = @($warnings)
        ValidatedAtUtc = [DateTime]::UtcNow.ToString('o')
        ValidatorVersion = $script:ToolkitVersion
    }
}

Export-ModuleMember -Function @(
    'Get-AzStorageSyncToolkitVersion',
    'Test-AzStorageSyncConfiguration'
)

