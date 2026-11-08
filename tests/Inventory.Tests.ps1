$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

Describe 'Disk-backed inventory and comparison' {
    It 'creates a complete redacted inventory' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncInventory-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $inventory = Join-Path $root 'inventory'
        [void](New-Item -ItemType Directory -Path (Join-Path $source 'Finance') -Force)
        try {
            [IO.File]::WriteAllText((Join-Path $source 'hello.txt'), 'hello')
            $unicodeName = 'r' + [char]0x00e9 + 'sum' + [char]0x00e9 + '.txt'
            [IO.File]::WriteAllText((Join-Path $source ('Finance\' + $unicodeName)), 'synthetic')

            $result = New-AzStorageSyncInventory -SourcePath $source -InventoryPath $inventory -BucketCount 8
            $manifestText = Get-Content -LiteralPath (Join-Path $inventory 'manifest.json') -Raw
            $manifest = $manifestText | ConvertFrom-Json

            $result.FileCount | Should -Be 2
            $manifest.Complete | Should -BeTrue
            $manifest.SourceRoot | Should -Be '[SOURCE]'
            $manifestText | Should -Not -Match ([regex]::Escape($source))
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'classifies new modified missing and unchanged files' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncCompare-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $baseline = Join-Path $root 'baseline'
        $current = Join-Path $root 'current'
        $delta = Join-Path $root 'delta'
        [void](New-Item -ItemType Directory -Path $source -Force)
        try {
            [IO.File]::WriteAllText((Join-Path $source 'unchanged.txt'), 'same')
            [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
            [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'remove me')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8)

            [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after with a different length')
            Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
            [IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)

            $result = Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta
            $result.NewCount | Should -Be 1
            $result.ModifiedCount | Should -Be 1
            $result.MissingCandidateCount | Should -Be 1
            $result.UnchangedCount | Should -Be 1
            (Get-Content -LiteralPath (Join-Path $delta 'manifest.json') -Raw) | Should -Not -Match ([regex]::Escape($source))
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'produces an unchanged-only delta for equivalent inventories' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncStable-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $first = Join-Path $root 'first'
        $second = Join-Path $root 'second'
        $delta = Join-Path $root 'delta'
        [void](New-Item -ItemType Directory -Path $source -Force)
        try {
            [IO.File]::WriteAllText((Join-Path $source 'stable.txt'), 'stable')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $first -BucketCount 4)
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $second -BucketCount 4)
            $result = Compare-AzStorageSyncInventory -PreviousInventoryPath $first -CurrentInventoryPath $second -OutputPath $delta

            $result.NewCount | Should -Be 0
            $result.ModifiedCount | Should -Be 0
            $result.MissingCandidateCount | Should -Be 0
            $result.UnchangedCount | Should -Be 1
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects an inventory path inside the source' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncUnsafe-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        [void](New-Item -ItemType Directory -Path $source -Force)
        try {
            { New-AzStorageSyncInventory -SourcePath $source -InventoryPath (Join-Path $source 'inventory') } | Should -Throw
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects comparison output inside an inventory' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncDeltaUnsafe-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $first = Join-Path $root 'first'
        $second = Join-Path $root 'second'
        [void](New-Item -ItemType Directory -Path $source -Force)
        try {
            [IO.File]::WriteAllText((Join-Path $source 'stable.txt'), 'stable')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $first -BucketCount 4)
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $second -BucketCount 4)

            { Compare-AzStorageSyncInventory -PreviousInventoryPath $first -CurrentInventoryPath $second -OutputPath (Join-Path $first 'delta') } | Should -Throw
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
