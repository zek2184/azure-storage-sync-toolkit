function New-AzStorageSyncPreviewPlan {
    <#
    .SYNOPSIS
    Creates an immutable, policy-evaluated preview plan from a delta.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DeltaPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CurrentInventoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputPath,
        [hashtable]$Policy
    )

    $deltaManifest = Read-ToolkitJson -Path (Join-Path $DeltaPath 'manifest.json')
    $currentManifest = Get-InventoryManifest -InventoryPath $CurrentInventoryPath
    if ([string]$deltaManifest.SchemaVersion -ne '1.0' -or -not [bool]$deltaManifest.Complete) {
        throw 'The delta is incomplete or uses an unsupported schema.'
    }
    if ([string]$deltaManifest.CurrentInventoryId -ne [string]$currentManifest.InventoryId) {
        throw 'DeltaPath does not reference CurrentInventoryPath.'
    }

    $deltaFullPath = Get-CanonicalToolkitPath -Path $DeltaPath
    $currentFullPath = Get-CanonicalToolkitPath -Path $CurrentInventoryPath
    $outputFullPath = Get-CanonicalToolkitPath -Path $OutputPath
    if ((Test-ToolkitPathWithinRoot -CandidatePath $outputFullPath -RootPath $deltaFullPath) -or
        (Test-ToolkitPathWithinRoot -CandidatePath $outputFullPath -RootPath $currentFullPath)) {
        throw 'OutputPath must not be inside the delta or current inventory path.'
    }
    if (Test-Path -LiteralPath $outputFullPath) {
        throw 'OutputPath already exists. Use a new path to preserve prior evidence.'
    }
    if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Create immutable preview plan')) { return }

    $normalizedPolicy = Get-NormalizedPreviewPolicy -Policy $Policy
    $policyJson = $normalizedPolicy | ConvertTo-Json -Depth 5 -Compress
    $policyFingerprint = Get-ToolkitSha256ForString -Value $policyJson
    [void](New-Item -ItemType Directory -Path $outputFullPath -Force)
    $itemsPath = Join-Path $outputFullPath 'plan-items.tsv'
    $csvPath = Join-Path $outputFullPath 'preview.csv'
    $itemsWriter = Get-ToolkitUtf8Writer -Path $itemsPath
    $csvWriter = Get-ToolkitUtf8Writer -Path $csvPath
    $itemsWriter.WriteLine("PathToken`tChangeType`tLength`tDecision`tEligible`tIssueCodes")
    $csvWriter.WriteLine('"RelativePath","ChangeType","Length","Decision","Eligible","IssueCodes"')

    [int64]$readyCount = 0
    [int64]$reviewCount = 0
    [int64]$blockedCount = 0
    [int64]$evidenceOnlyCount = 0

    try {
        foreach ($definition in @(
            @{ Path = (Join-Path $DeltaPath 'new.tsv'); ChangeType = 'New'; LengthIndex = 1 },
            @{ Path = (Join-Path $DeltaPath 'modified.tsv'); ChangeType = 'Modified'; LengthIndex = 2 }
        )) {
            $reader = [IO.File]::OpenText([string]$definition.Path)
            try {
                [void]$reader.ReadLine()
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = $line.Split([char]9)
                    $pathToken = $parts[0]
                    $relativePath = ConvertFrom-InventoryPathToken -Token $pathToken
                    $length = [int64]$parts[[int]$definition.LengthIndex]
                    $decision = Get-PreviewPolicyDecision -RelativePath $relativePath -Length $length -Policy $normalizedPolicy
                    switch ($decision.Decision) {
                        'Ready' { $readyCount++ }
                        'Review' { $reviewCount++ }
                        'Blocked' { $blockedCount++ }
                    }
                    $itemsWriter.WriteLine(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f
                        $pathToken, $definition.ChangeType, $length, $decision.Decision,
                        ([string]$decision.Eligible).ToLowerInvariant(), $decision.IssueCodes))
                    $csvWriter.WriteLine((@(
                        ConvertTo-ToolkitCsvField $relativePath
                        ConvertTo-ToolkitCsvField ([string]$definition.ChangeType)
                        ConvertTo-ToolkitCsvField ([string]$length)
                        ConvertTo-ToolkitCsvField ([string]$decision.Decision)
                        ConvertTo-ToolkitCsvField (([string]$decision.Eligible).ToLowerInvariant())
                        ConvertTo-ToolkitCsvField ([string]$decision.IssueCodes)
                    ) -join ','))
                }
            }
            finally { $reader.Dispose() }
        }

        $missingReader = [IO.File]::OpenText((Join-Path $DeltaPath 'missing-candidates.tsv'))
        try {
            [void]$missingReader.ReadLine()
            while ($null -ne ($line = $missingReader.ReadLine())) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line.Split([char]9)
                $pathToken = $parts[0]
                $relativePath = ConvertFrom-InventoryPathToken -Token $pathToken
                $length = [int64]$parts[1]
                $itemsWriter.WriteLine(("{0}`tMissingCandidate`t{1}`tEvidenceOnly`tfalse`tNO_DELETE_ACTION" -f $pathToken, $length))
                $csvWriter.WriteLine((@(
                    ConvertTo-ToolkitCsvField $relativePath
                    ConvertTo-ToolkitCsvField 'MissingCandidate'
                    ConvertTo-ToolkitCsvField ([string]$length)
                    ConvertTo-ToolkitCsvField 'EvidenceOnly'
                    ConvertTo-ToolkitCsvField 'false'
                    ConvertTo-ToolkitCsvField 'NO_DELETE_ACTION'
                ) -join ','))
                $evidenceOnlyCount++
            }
        }
        finally { $missingReader.Dispose() }
    }
    finally {
        $itemsWriter.Dispose()
        $csvWriter.Dispose()
    }

    $itemsFingerprint = Get-ToolkitSha256ForFile -Path $itemsPath
    $csvFingerprint = Get-ToolkitSha256ForFile -Path $csvPath
    $planMaterial = @(
        '1.0',
        [string]$deltaManifest.DeltaId,
        [string]$currentManifest.InventoryId,
        $policyFingerprint,
        $itemsFingerprint,
        $csvFingerprint
    ) -join '|'
    $planId = Get-ToolkitSha256ForString -Value $planMaterial

    $manifest = [ordered]@{
        SchemaVersion = '1.0'
        PlanId = $planId
        ToolkitVersion = $script:ToolkitVersion
        Complete = $true
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        DeltaId = [string]$deltaManifest.DeltaId
        CurrentInventoryId = [string]$currentManifest.InventoryId
        Policy = $normalizedPolicy
        PolicyFingerprint = $policyFingerprint
        ItemsFingerprint = $itemsFingerprint
        CsvFingerprint = $csvFingerprint
        ReadyCount = $readyCount
        ReviewCount = $reviewCount
        BlockedCount = $blockedCount
        EvidenceOnlyCount = $evidenceOnlyCount
        MissingCandidateAction = 'None'
    }
    Write-ToolkitJson -Path (Join-Path $outputFullPath 'manifest.json') -Value $manifest

    return [pscustomobject]@{
        PlanId = $planId
        OutputPath = $outputFullPath
        ReadyCount = $readyCount
        ReviewCount = $reviewCount
        BlockedCount = $blockedCount
        EvidenceOnlyCount = $evidenceOnlyCount
    }
}

function Test-AzStorageSyncPreviewPlan {
    <#
    .SYNOPSIS
    Verifies a preview plan's fingerprints and source evidence identifiers.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PlanPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DeltaPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CurrentInventoryPath
    )

    $errors = New-Object System.Collections.Generic.List[string]
    try { $plan = Read-ToolkitJson -Path (Join-Path $PlanPath 'manifest.json') }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{ IsValid = $false; PlanId = $null; Errors = @($errors) }
    }
    $delta = Read-ToolkitJson -Path (Join-Path $DeltaPath 'manifest.json')
    $current = Get-InventoryManifest -InventoryPath $CurrentInventoryPath

    if (-not [bool]$plan.Complete) { $errors.Add('Plan is not marked complete.') }
    if ([string]$plan.DeltaId -ne [string]$delta.DeltaId) { $errors.Add('Plan DeltaId does not match the supplied delta.') }
    if ([string]$plan.CurrentInventoryId -ne [string]$current.InventoryId) { $errors.Add('Plan CurrentInventoryId does not match the supplied inventory.') }

    $itemsPath = Join-Path $PlanPath 'plan-items.tsv'
    $csvPath = Join-Path $PlanPath 'preview.csv'
    try {
        $itemsFingerprint = Get-ToolkitSha256ForFile -Path $itemsPath
        $csvFingerprint = Get-ToolkitSha256ForFile -Path $csvPath
        if ($itemsFingerprint -ne [string]$plan.ItemsFingerprint) { $errors.Add('Plan items fingerprint does not match.') }
        if ($csvFingerprint -ne [string]$plan.CsvFingerprint) { $errors.Add('Preview CSV fingerprint does not match.') }

        $policyJson = $plan.Policy | ConvertTo-Json -Depth 5 -Compress
        $policyFingerprint = Get-ToolkitSha256ForString -Value $policyJson
        if ($policyFingerprint -ne [string]$plan.PolicyFingerprint) { $errors.Add('Policy fingerprint does not match.') }

        $planMaterial = @(
            [string]$plan.SchemaVersion,
            [string]$plan.DeltaId,
            [string]$plan.CurrentInventoryId,
            $policyFingerprint,
            $itemsFingerprint,
            $csvFingerprint
        ) -join '|'
        $expectedPlanId = Get-ToolkitSha256ForString -Value $planMaterial
        if ($expectedPlanId -ne [string]$plan.PlanId) { $errors.Add('PlanId does not match the plan evidence.') }
    }
    catch { $errors.Add($_.Exception.Message) }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        PlanId = [string]$plan.PlanId
        Errors = @($errors)
    }
}
