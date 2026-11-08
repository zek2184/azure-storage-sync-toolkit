# ADR 0001: Filesystem-first public release

- Status: Accepted for foundation milestone
- Date: 2026-11-08

## Context

The portfolio project must demonstrate safe incremental migration behavior while remaining reproducible without client environments, cloud credentials, or paid Azure resources.

## Decision

Version 1 will use a filesystem transfer provider for local, UNC, and mounted Azure Files paths. Native Azure Blob and AzCopy support will be added through a later provider contract after inventory, safety, state, and reporting behavior is stable.

## Consequences

- The first release can be developed and tested entirely with synthetic local data.
- Windows PowerShell 5.1 compatibility remains an explicit constraint.
- The public README must not imply native Azure Blob support in version 1.
- Provider boundaries must avoid coupling comparison and state logic to Robocopy or AzCopy.

