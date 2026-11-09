# Contributing

## Before changing code

1. Confirm the relevant requirement and acceptance criterion.
2. Record a design decision when behavior, compatibility, security, or public interfaces change.
3. Use synthetic data and keep the clean-room boundary intact.

## Development checks

```powershell
./scripts/Test-Foundation.ps1
pwsh -NoProfile -File ./scripts/Invoke-Quality.ps1 -RequirePester -RequireAnalyzer
```

The full quality gate requires PowerShell 7, Pester 5 or later, and PSScriptAnalyzer. The toolkit's version 1 filesystem provider remains compatible with Windows PowerShell 5.1.

Changes should include tests for normal behavior, validation failures, and recovery behavior where applicable. Documentation must be updated in the same change when public behavior changes.

## Commit hygiene

- Do not commit generated reports, runtime state, logs, local configuration, secrets, or screenshots containing local paths.
- Keep commits focused and describe the behavior changed.
- Review the staged diff for personal or client information before committing.

