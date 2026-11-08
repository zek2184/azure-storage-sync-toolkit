$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

Describe 'Immutable preview plans' {
    BeforeAll {
function New-PreviewTestFixture {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncPreview-' + [Guid]::NewGuid().ToString('N'))
    if (-not $PSCmdlet.ShouldProcess($root, 'Create synthetic preview test fixture')) { return }
    $source = Join-Path $root 'source'
    $baseline = Join-Path $root 'baseline'
    $current = Join-Path $root 'current'
    $delta = Join-Path $root 'delta'
    $plan = Join-Path $root 'plan'
    [void](New-Item -ItemType Directory -Path $source -Force)

    [IO.File]::WriteAllText((Join-Path $source 'unchanged.txt'), 'same')
    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
    [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'remove')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8)

    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after with a different length')
    Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
    [IO.File]::WriteAllText((Join-Path $source 'ready.txt'), 'ready')
    [IO.File]::WriteAllText((Join-Path $source 'blocked.exe'), 'blocked')
    [IO.File]::WriteAllText((Join-Path $source 'review.pst'), 'review')
    [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)
    [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta)

    $result = New-AzStorageSyncPreviewPlan -DeltaPath $delta -CurrentInventoryPath $current -OutputPath $plan -Policy @{
        BlockedExtensions = @('.exe')
        ReviewExtensions = @('.pst')
    }
    return [pscustomobject]@{
        Root = $root
        Source = $source
        Current = $current
        Delta = $delta
        Plan = $plan
        Result = $result
    }
}
    }

    It 'classifies ready review blocked and evidence-only items' {
        $fixture = New-PreviewTestFixture
        try {
            $fixture.Result.ReadyCount | Should -Be 2
            $fixture.Result.ReviewCount | Should -Be 1
            $fixture.Result.BlockedCount | Should -Be 1
            $fixture.Result.EvidenceOnlyCount | Should -Be 1

            $validation = Test-AzStorageSyncPreviewPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta -CurrentInventoryPath $fixture.Current
            $validation.IsValid | Should -BeTrue
            $validation.PlanId | Should -Be $fixture.Result.PlanId
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'does not place the absolute source root in plan artifacts' {
        $fixture = New-PreviewTestFixture
        try {
            $artifactText = @(
                Get-Content -LiteralPath (Join-Path $fixture.Plan 'manifest.json') -Raw
                Get-Content -LiteralPath (Join-Path $fixture.Plan 'plan-items.tsv') -Raw
                Get-Content -LiteralPath (Join-Path $fixture.Plan 'preview.csv') -Raw
            ) -join [Environment]::NewLine
            $artifactText | Should -Not -Match ([regex]::Escape($fixture.Source))
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'detects tampered plan items' {
        $fixture = New-PreviewTestFixture
        try {
            Add-Content -LiteralPath (Join-Path $fixture.Plan 'plan-items.tsv') -Value 'tampered'
            $validation = Test-AzStorageSyncPreviewPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta -CurrentInventoryPath $fixture.Current
            $validation.IsValid | Should -BeFalse
            $validation.Errors | Should -Contain 'Plan items fingerprint does not match.'
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'detects a stale current inventory' {
        $fixture = New-PreviewTestFixture
        $newCurrent = Join-Path $fixture.Root 'new-current'
        try {
            [IO.File]::WriteAllText((Join-Path $fixture.Source 'later.txt'), 'later')
            [void](New-AzStorageSyncInventory -SourcePath $fixture.Source -InventoryPath $newCurrent -BucketCount 8)
            $validation = Test-AzStorageSyncPreviewPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta -CurrentInventoryPath $newCurrent
            $validation.IsValid | Should -BeFalse
            $validation.Errors | Should -Contain 'Plan CurrentInventoryId does not match the supplied inventory.'
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'neutralizes spreadsheet formula characters in the preview CSV' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncCsvSafe-' + [Guid]::NewGuid().ToString('N'))
        $source = Join-Path $root 'source'
        $baseline = Join-Path $root 'baseline'
        $current = Join-Path $root 'current'
        $delta = Join-Path $root 'delta'
        $plan = Join-Path $root 'plan'
        [void](New-Item -ItemType Directory -Path $source -Force)
        try {
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 4)
            [IO.File]::WriteAllText((Join-Path $source '=formula.txt'), 'synthetic')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 4)
            [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta)
            [void](New-AzStorageSyncPreviewPlan -DeltaPath $delta -CurrentInventoryPath $current -OutputPath $plan)

            $csv = Get-Content -LiteralPath (Join-Path $plan 'preview.csv') -Raw
            $csv | Should -Match ([regex]::Escape("'=" + 'formula.txt'))
            $csv | Should -Not -Match '"=formula\.txt"'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
