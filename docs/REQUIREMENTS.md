# Requirements and acceptance criteria

## Objective

Provide a safe, reproducible way to inventory a file source, preview incremental changes, copy approved candidates, and prove an unchanged rerun has no remaining candidates.

## Version 1 requirements

- Support local, UNC, and mounted Azure Files paths through a filesystem provider.
- Keep inventory, comparison, safety policy, transfer, state, and reporting separated.
- Default to preview and require an explicit apply action.
- Reject delete, mirror, move, rename, purge, and ACL-copy behavior.
- Preserve the last successful baseline after failure or cancellation.
- Generate redacted JSON, CSV, HTML, and structured status output.
- Provide deterministic synthetic baseline, delta, failure, recovery, and no-op scenarios.
- Maintain Windows PowerShell 5.1 compatibility for the filesystem provider.

## Acceptance criteria

1. A fresh machine can run the synthetic demo using documented commands.
2. Preview classifies new, modified, missing-candidate, unchanged, blocked, and failed items correctly.
3. Apply copies only eligible new and modified items.
4. Automated tests reject destructive transfer options.
5. An injected copy failure leaves the prior successful baseline unchanged.
6. A successful apply followed by an unchanged rerun reports zero copy candidates.
7. Tests cover validation, normalization, comparison, policy, state promotion, redaction, and reports.
8. Public artifacts contain only generated synthetic data and pass privacy and secret review.
9. Documentation covers quick start, architecture, limitations, security, testing, and troubleshooting.
10. Every portfolio screenshot is reproducible from a documented synthetic run.

## Publication gate

Implementation completion does not authorize publication. GitHub visibility changes, cloud resource creation, screenshots, Upwork edits, and proposals require explicit approval.

