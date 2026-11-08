[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$moduleManifest = Join-Path $repositoryRoot 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'

$manifest = Test-ModuleManifest -Path $moduleManifest -ErrorAction Stop
if ([string]$manifest.Version -ne '0.2.0') {
    throw "Unexpected module version: $($manifest.Version)"
}

Import-Module $moduleManifest -Force -ErrorAction Stop

if ((Get-AzStorageSyncToolkitVersion) -ne '0.2.0') {
    throw 'The exported toolkit version is incorrect.'
}

$safe = Test-AzStorageSyncConfiguration -Configuration @{
    SourcePath = 'C:\SyntheticDemo\Source'
    DestinationPath = 'C:\SyntheticDemo\Destination'
    WorkingPath = 'C:\SyntheticDemo\Working'
    Provider = 'FileSystem'
    TransferOptions = @('/E', '/COPY:DAT')
}
if (-not $safe.IsValid) {
    throw "Safe configuration failed: $($safe.Errors -join '; ')"
}

foreach ($unsafeOption in @('/MIR', '/PURGE', '/MOVE', '/MOV', '/COPYALL', '/SEC', '/SECFIX')) {
    $unsafe = Test-AzStorageSyncConfiguration -Configuration @{
        SourcePath = 'C:\SyntheticDemo\Source'
        DestinationPath = 'C:\SyntheticDemo\Destination'
        WorkingPath = 'C:\SyntheticDemo\Working'
        Provider = 'FileSystem'
        TransferOptions = @($unsafeOption)
    }
    if ($unsafe.IsValid) {
        throw "Unsafe option was accepted: $unsafeOption"
    }
}

Write-Output 'PASS: module manifest, import, version, safe configuration, and destructive-option rejection.'

