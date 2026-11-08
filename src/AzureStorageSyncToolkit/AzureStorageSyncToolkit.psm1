Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ToolkitVersion = '0.3.0'
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

$privateScripts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' | Sort-Object Name)
$publicScripts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' | Sort-Object Name)

foreach ($scriptFile in @($privateScripts + $publicScripts)) {
    . $scriptFile.FullName
}

Export-ModuleMember -Function @(
    'Get-AzStorageSyncToolkitVersion',
    'Test-AzStorageSyncConfiguration',
    'New-AzStorageSyncInventory',
    'Compare-AzStorageSyncInventory',
    'New-AzStorageSyncPreviewPlan',
    'Test-AzStorageSyncPreviewPlan'
)

