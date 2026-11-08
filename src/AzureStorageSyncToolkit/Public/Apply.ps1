function Invoke-AzStorageSyncPlan {
    <#
    .SYNOPSIS
    Applies only Ready items from an explicitly approved preview plan.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PlanPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DeltaPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CurrentInventoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SourcePath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DestinationPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StatePath,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ApprovedPlanId,
        [Parameter(DontShow = $true)][ValidateRange(-1, 1000000)][int]$TestFailureAfter = -1
    )

    $validation = Test-AzStorageSyncPreviewPlan -PlanPath $PlanPath -DeltaPath $DeltaPath -CurrentInventoryPath $CurrentInventoryPath
    if (-not $validation.IsValid) { throw "Preview plan validation failed: $($validation.Errors -join '; ')" }
    if ($validation.PlanId -ne $ApprovedPlanId) { throw 'ApprovedPlanId does not match the validated preview plan.' }

    $planManifest = Read-ToolkitJson -Path (Join-Path $PlanPath 'manifest.json')
    $currentManifest = Get-InventoryManifest -InventoryPath $CurrentInventoryPath
    $sourceRoot = Get-CanonicalToolkitPath -Path $SourcePath
    $destinationRoot = Get-CanonicalToolkitPath -Path $DestinationPath
    $stateRoot = Get-CanonicalToolkitPath -Path $StatePath
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw 'SourcePath must identify an existing directory.' }
    if ((Test-ToolkitPathWithinRoot -CandidatePath $destinationRoot -RootPath $sourceRoot) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $sourceRoot -RootPath $destinationRoot)) {
        throw 'SourcePath and DestinationPath must not be equal or nested.'
    }
    if ((Test-ToolkitPathWithinRoot -CandidatePath $stateRoot -RootPath $sourceRoot) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $sourceRoot -RootPath $stateRoot) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $stateRoot -RootPath $destinationRoot) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $destinationRoot -RootPath $stateRoot)) {
        throw 'StatePath must not be equal to or nested with SourcePath or DestinationPath.'
    }
    foreach ($evidencePath in @($PlanPath, $DeltaPath, $CurrentInventoryPath)) {
        $evidenceRoot = Get-CanonicalToolkitPath -Path $evidencePath
        if ((Test-ToolkitPathWithinRoot -CandidatePath $stateRoot -RootPath $evidenceRoot) -or
            (Test-ToolkitPathWithinRoot -CandidatePath $evidenceRoot -RootPath $stateRoot)) {
            throw 'StatePath must not be equal to or nested with plan, delta, or inventory evidence.'
        }
    }

    $planItemsPath = Join-Path $PlanPath 'plan-items.tsv'
    [int64]$readyRecordCount = 0
    Get-PreviewPlanReadyRecord -PlanItemsPath $planItemsPath | ForEach-Object {
        [void](Assert-ToolkitSourceRecord -SourceRoot $sourceRoot -Record $_)
        $readyRecordCount++
    }
    if ($readyRecordCount -ne [int64]$planManifest.ReadyCount) {
        throw 'The number of Ready plan records does not match the plan manifest.'
    }

    if (-not $PSCmdlet.ShouldProcess($destinationRoot, "Apply approved plan $ApprovedPlanId with $readyRecordCount Ready item(s)")) {
        return
    }

    [void](New-Item -ItemType Directory -Path $destinationRoot -Force)
    [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    $lockPath = Join-Path $stateRoot 'apply.lock'
    $lockStream = $null
    try {
        $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch { throw 'Another apply operation appears to be active for this StatePath.' }

    $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $runPath = Join-Path (Join-Path $stateRoot 'runs') $runId
    [void](New-Item -ItemType Directory -Path $runPath -Force)
    $resultsPath = Join-Path $runPath 'results.tsv'
    $resultsWriter = Get-ToolkitUtf8Writer -Path $resultsPath
    $resultsWriter.WriteLine("PathToken`tChangeType`tStatus`tMessage")
    [int64]$copiedCount = 0
    [int64]$alreadyCurrentCount = 0
    [int64]$failedCount = 0
    $startedUtc = [DateTime]::UtcNow
    $runStatus = 'Running'
    $failureMessage = ''

    try {
        Get-PreviewPlanReadyRecord -PlanItemsPath $planItemsPath | ForEach-Object {
            $record = $_
            try {
                if ($TestFailureAfter -ge 0 -and ($copiedCount + $alreadyCurrentCount) -ge $TestFailureAfter) {
                    throw 'Injected transfer failure for deterministic testing.'
                }
                $sourceFile = Assert-ToolkitSourceRecord -SourceRoot $sourceRoot -Record $record
                $destinationFile = Resolve-ToolkitRelativeFilePath -RootPath $destinationRoot -RelativePath $record.RelativePath
                $destinationParent = Split-Path -Parent $destinationFile
                if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $destinationParent -Force)
                }

                $alreadyCurrent = $false
                if (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
                    $destinationItem = Get-Item -LiteralPath $destinationFile -Force
                    $alreadyCurrent = ([int64]$destinationItem.Length -eq [int64]$record.Length -and
                        [int64]$destinationItem.LastWriteTimeUtc.Ticks -eq [int64]$record.LastWriteTimeUtcTicks)
                }

                if ($alreadyCurrent) {
                    $alreadyCurrentCount++
                    $resultsWriter.WriteLine(("{0}`t{1}`tAlreadyCurrent`tNo copy required." -f $record.PathToken, $record.ChangeType))
                }
                else {
                    [IO.File]::Copy($sourceFile, $destinationFile, $true)
                    [IO.File]::SetLastWriteTimeUtc($destinationFile, [DateTime]$record.LastWriteTimeUtcTicks)
                    $copiedCount++
                    $resultsWriter.WriteLine(("{0}`t{1}`tCopied`tCopy completed." -f $record.PathToken, $record.ChangeType))
                }
            }
            catch {
                $failedCount++
                $itemError = $_.Exception.Message.Replace($sourceRoot, '[SOURCE]').Replace($destinationRoot, '[DESTINATION]').Replace("`r", ' ').Replace("`n", ' ').Replace("`t", ' ')
                $resultsWriter.WriteLine(("{0}`t{1}`tFailed`t{2}" -f $record.PathToken, $record.ChangeType, $itemError))
                throw
            }
        }

        $baselinePath = Copy-ToolkitInventoryToState -InventoryPath $CurrentInventoryPath -StatePath $stateRoot -InventoryId ([string]$currentManifest.InventoryId)
        $pointer = [ordered]@{
            SchemaVersion = '1.0'
            InventoryId = [string]$currentManifest.InventoryId
            RelativeBaselinePath = 'baselines/' + [string]$currentManifest.InventoryId
            PlanId = $ApprovedPlanId
            RunId = $runId
            PromotedUtc = [DateTime]::UtcNow.ToString('o')
        }
        Write-ToolkitAtomicJson -Path (Join-Path $stateRoot 'current.json') -Value $pointer
        $runStatus = 'Completed'
    }
    catch {
        if ($failedCount -eq 0) { $failedCount++ }
        $failureMessage = $_.Exception.Message.Replace($sourceRoot, '[SOURCE]').Replace($destinationRoot, '[DESTINATION]').Replace($stateRoot, '[STATE]')
        foreach ($evidencePath in @($PlanPath, $DeltaPath, $CurrentInventoryPath)) {
            $failureMessage = $failureMessage.Replace((Get-CanonicalToolkitPath -Path $evidencePath), '[EVIDENCE]')
        }
        $runStatus = 'Failed'
        throw
    }
    finally {
        $resultsWriter.Dispose()
        $runManifest = [ordered]@{
            SchemaVersion = '1.0'
            RunId = $runId
            Status = $runStatus
            PlanId = $ApprovedPlanId
            CurrentInventoryId = [string]$currentManifest.InventoryId
            StartedUtc = $startedUtc.ToString('o')
            CompletedUtc = [DateTime]::UtcNow.ToString('o')
            CopiedCount = $copiedCount
            AlreadyCurrentCount = $alreadyCurrentCount
            FailedCount = $failedCount
            FailureMessage = $failureMessage
            ResultsFingerprint = Get-ToolkitSha256ForFile -Path $resultsPath
            MissingCandidateAction = 'None'
        }
        Write-ToolkitJson -Path (Join-Path $runPath 'manifest.json') -Value $runManifest
        if ($null -ne $lockStream) { $lockStream.Dispose() }
    }

    return [pscustomobject]@{
        RunId = $runId
        Status = $runStatus
        RunPath = $runPath
        BaselinePath = $baselinePath
        CopiedCount = $copiedCount
        AlreadyCurrentCount = $alreadyCurrentCount
        FailedCount = $failedCount
        InventoryId = [string]$currentManifest.InventoryId
    }
}
