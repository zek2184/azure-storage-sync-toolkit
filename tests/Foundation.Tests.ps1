$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

Describe 'AzureStorageSyncToolkit foundation' {
    It 'exports the expected version' {
        Get-AzStorageSyncToolkitVersion | Should -Be '0.1.0'
    }

    It 'accepts a safe foundation configuration' {
        $result = Test-AzStorageSyncConfiguration -Configuration @{
            SourcePath = 'C:\SyntheticDemo\Source'
            DestinationPath = 'C:\SyntheticDemo\Destination'
            WorkingPath = 'C:\SyntheticDemo\Working'
            Provider = 'FileSystem'
            TransferOptions = @('/E', '/COPY:DAT')
        }

        $result.IsValid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It 'rejects a missing required value' {
        $result = Test-AzStorageSyncConfiguration -Configuration @{
            SourcePath = 'C:\SyntheticDemo\Source'
            DestinationPath = 'C:\SyntheticDemo\Destination'
            Provider = 'FileSystem'
        }

        $result.IsValid | Should -BeFalse
        $result.Errors | Should -Contain 'Missing required configuration value: WorkingPath'
    }

    It 'rejects destructive transfer options' {
        foreach ($unsafeOption in @('/MIR', '/PURGE', '/MOVE', '/MOV', '/COPYALL', '/SEC', '/SECFIX')) {
            $result = Test-AzStorageSyncConfiguration -Configuration @{
                SourcePath = 'C:\SyntheticDemo\Source'
                DestinationPath = 'C:\SyntheticDemo\Destination'
                WorkingPath = 'C:\SyntheticDemo\Working'
                Provider = 'FileSystem'
                TransferOptions = @($unsafeOption)
            }

            $result.IsValid | Should -BeFalse
            $result.Errors | Should -Contain "Prohibited transfer option: $unsafeOption"
        }
    }

    It 'rejects identical source and destination paths' {
        $result = Test-AzStorageSyncConfiguration -Configuration @{
            SourcePath = 'C:\SyntheticDemo\Same'
            DestinationPath = 'C:\SyntheticDemo\Same'
            WorkingPath = 'C:\SyntheticDemo\Working'
            Provider = 'FileSystem'
            TransferOptions = @('/E')
        }

        $result.IsValid | Should -BeFalse
        $result.Errors | Should -Contain 'SourcePath and DestinationPath must be different.'
    }
}

