# Azure Storage Migration & Incremental Sync Toolkit

A clean-room PowerShell toolkit for safely inventorying file sources, previewing incremental changes, applying approved non-destructive copies, and producing auditable reports.

> **Status:** foundation milestone. Inventory, comparison, transfer, and dashboard features are not implemented yet.

## Version 1 target

The first release will support local, UNC, and mounted Azure Files paths on Windows. Native Azure Blob/AzCopy support is intentionally deferred until the core safety, state, and reporting contracts are stable.

## Safety principles

- Preview is the default.
- Apply will require an explicit, current preview-plan identifier.
- Version 1 will not delete, mirror, move, rename, or replicate ACLs.
- Failed or cancelled transfers will not replace the last successful baseline.
- Public demonstrations will use generated synthetic data only.

## Foundation quick start

```powershell
Import-Module ./src/AzureStorageSyncToolkit/AzureStorageSyncToolkit.psd1 -Force
Get-AzStorageSyncToolkitVersion

$config = @{
    SourcePath = 'C:\SyntheticDemo\Source'
    DestinationPath = 'C:\SyntheticDemo\Destination'
    WorkingPath = 'C:\SyntheticDemo\Working'
    Provider = 'FileSystem'
    TransferOptions = @('/E', '/COPY:DAT')
}

Test-AzStorageSyncConfiguration -Configuration $config
```

Run the dependency-free foundation verification:

```powershell
./scripts/Test-Foundation.ps1
```

Run the complete quality gate after installing Pester 5 and PSScriptAnalyzer:

```powershell
./scripts/Invoke-Quality.ps1 -RequirePester -RequireAnalyzer
```

## Documentation

- [Requirements and acceptance criteria](docs/REQUIREMENTS.md)
- [Architecture decision: filesystem-first release](docs/decisions/0001-filesystem-first.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Clean-room statement

This project starts with new source history and synthetic examples. It does not include code, reports, screenshots, metrics, paths, or configuration copied from a private or client environment.

