$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1'
Import-Module $modulePath -Force

Describe 'Approved non-destructive apply' {
    BeforeAll {
        function New-ApplyTestFixture {
            [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
            param()

            $root = Join-Path ([IO.Path]::GetTempPath()) ('AzSyncApply-' + [Guid]::NewGuid().ToString('N'))
            if (-not $PSCmdlet.ShouldProcess($root, 'Create synthetic apply test fixture')) { return }
            $source = Join-Path $root 'source'
            $destination = Join-Path $root 'destination'
            $state = Join-Path $root 'state'
            $baseline = Join-Path $root 'baseline'
            $current = Join-Path $root 'current'
            $delta = Join-Path $root 'delta'
            $plan = Join-Path $root 'plan'
            [void](New-Item -ItemType Directory -Path $source, $destination -Force)

            [IO.File]::WriteAllText((Join-Path $source 'stable.txt'), 'stable')
            [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
            [IO.File]::WriteAllText((Join-Path $source 'missing.txt'), 'must remain at destination')
            Copy-Item -LiteralPath (Join-Path $source 'stable.txt') -Destination $destination
            Copy-Item -LiteralPath (Join-Path $source 'modified.txt') -Destination $destination
            Copy-Item -LiteralPath (Join-Path $source 'missing.txt') -Destination $destination
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $baseline -BucketCount 8)

            [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after with a different length')
            Remove-Item -LiteralPath (Join-Path $source 'missing.txt')
            [IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new')
            [void](New-AzStorageSyncInventory -SourcePath $source -InventoryPath $current -BucketCount 8)
            [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $baseline -CurrentInventoryPath $current -OutputPath $delta)
            $preview = New-AzStorageSyncPreviewPlan -DeltaPath $delta -CurrentInventoryPath $current -OutputPath $plan

            return [pscustomobject]@{
                Root = $root
                Source = $source
                Destination = $destination
                State = $state
                Baseline = $baseline
                Current = $current
                Delta = $delta
                Plan = $plan
                Preview = $preview
            }
        }
    }

    It 'copies only ready items and preserves missing destination files' {
        $fixture = New-ApplyTestFixture
        try {
            $result = Invoke-AzStorageSyncPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta `
                -CurrentInventoryPath $fixture.Current -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId $fixture.Preview.PlanId -Confirm:$false

            $result.Status | Should -Be 'Completed'
            $result.CopiedCount | Should -Be 2
            [IO.File]::ReadAllText((Join-Path $fixture.Destination 'modified.txt')) | Should -Be 'after with a different length'
            [IO.File]::ReadAllText((Join-Path $fixture.Destination 'new.txt')) | Should -Be 'new'
            Test-Path -LiteralPath (Join-Path $fixture.Destination 'missing.txt') | Should -BeTrue

            $pointer = Get-Content -LiteralPath (Join-Path $fixture.State 'current.json') -Raw | ConvertFrom-Json
            $pointer.InventoryId | Should -Be $result.InventoryId
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'rejects an unapproved plan identifier before copying' {
        $fixture = New-ApplyTestFixture
        try {
            { Invoke-AzStorageSyncPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta `
                -CurrentInventoryPath $fixture.Current -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId ('0' * 64) -Confirm:$false } | Should -Throw
            Test-Path -LiteralPath (Join-Path $fixture.Destination 'new.txt') | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'rejects source changes before copying' {
        $fixture = New-ApplyTestFixture
        try {
            [IO.File]::WriteAllText((Join-Path $fixture.Source 'new.txt'), 'changed after preview')
            { Invoke-AzStorageSyncPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta `
                -CurrentInventoryPath $fixture.Current -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId $fixture.Preview.PlanId -Confirm:$false } | Should -Throw
            Test-Path -LiteralPath (Join-Path $fixture.Destination 'new.txt') | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }

    It 'preserves the successful baseline after failure and supports retry' {
        $fixture = New-ApplyTestFixture
        try {
            $first = Invoke-AzStorageSyncPlan -PlanPath $fixture.Plan -DeltaPath $fixture.Delta `
                -CurrentInventoryPath $fixture.Current -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId $fixture.Preview.PlanId -Confirm:$false
            $pointerBefore = Get-Content -LiteralPath (Join-Path $fixture.State 'current.json') -Raw | ConvertFrom-Json

            [IO.File]::WriteAllText((Join-Path $fixture.Source 'later-one.txt'), 'one')
            [IO.File]::WriteAllText((Join-Path $fixture.Source 'later-two.txt'), 'two')
            $nextInventory = Join-Path $fixture.Root 'next-inventory'
            $nextDelta = Join-Path $fixture.Root 'next-delta'
            $nextPlan = Join-Path $fixture.Root 'next-plan'
            [void](New-AzStorageSyncInventory -SourcePath $fixture.Source -InventoryPath $nextInventory -BucketCount 8)
            [void](Compare-AzStorageSyncInventory -PreviousInventoryPath $first.BaselinePath -CurrentInventoryPath $nextInventory -OutputPath $nextDelta)
            $nextPreview = New-AzStorageSyncPreviewPlan -DeltaPath $nextDelta -CurrentInventoryPath $nextInventory -OutputPath $nextPlan

            { Invoke-AzStorageSyncPlan -PlanPath $nextPlan -DeltaPath $nextDelta `
                -CurrentInventoryPath $nextInventory -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId $nextPreview.PlanId -TestFailureAfter 1 -Confirm:$false } | Should -Throw

            $pointerAfterFailure = Get-Content -LiteralPath (Join-Path $fixture.State 'current.json') -Raw | ConvertFrom-Json
            $pointerAfterFailure.InventoryId | Should -Be $pointerBefore.InventoryId
            $failedRun = Get-ChildItem -LiteralPath (Join-Path $fixture.State 'runs') -Directory | ForEach-Object {
                Get-Content -LiteralPath (Join-Path $_.FullName 'manifest.json') -Raw | ConvertFrom-Json
            } | Where-Object Status -eq 'Failed' | Select-Object -First 1
            $failedRun.FailedCount | Should -Be 1

            $failedResultPath = Join-Path (Join-Path (Join-Path $fixture.State 'runs') $failedRun.RunId) 'results.tsv'
            (Get-Content -LiteralPath $failedResultPath -Raw) | Should -Match ([regex]::Escape("`tFailed`t"))

            $retry = Invoke-AzStorageSyncPlan -PlanPath $nextPlan -DeltaPath $nextDelta `
                -CurrentInventoryPath $nextInventory -SourcePath $fixture.Source `
                -DestinationPath $fixture.Destination -StatePath $fixture.State `
                -ApprovedPlanId $nextPreview.PlanId -Confirm:$false
            ($retry.CopiedCount + $retry.AlreadyCurrentCount) | Should -Be 2
            $retry.InventoryId | Should -Not -Be $pointerBefore.InventoryId
        }
        finally {
            if (Test-Path -LiteralPath $fixture.Root) { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }
    }
}
