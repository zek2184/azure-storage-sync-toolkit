@{
    RootModule = 'AzureStorageSyncToolkit.psm1'
    ModuleVersion = '0.2.0'
    GUID = '76dbf1c1-7c7a-4b86-9c1c-2f1297d3fc35'
    Author = 'Azure Storage Sync Toolkit contributors'
    CompanyName = 'Community'
    Copyright = '(c) 2026 Azure Storage Sync Toolkit contributors. MIT License.'
    Description = 'Clean-room, non-destructive Azure Files migration planning and incremental synchronization toolkit.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-AzStorageSyncToolkitVersion',
        'Test-AzStorageSyncConfiguration',
        'New-AzStorageSyncInventory',
        'Compare-AzStorageSyncInventory'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Azure', 'AzureFiles', 'Migration', 'PowerShell', 'Synchronization')
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://github.com/OWNER/azure-storage-sync-toolkit'
            ReleaseNotes = 'Adds disk-backed inventory and incremental comparison. Transfer features are not implemented.'
        }
    }
}

