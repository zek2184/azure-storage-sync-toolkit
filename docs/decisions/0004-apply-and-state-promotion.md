# ADR 0004: Approved apply and atomic state promotion

- Status: Accepted
- Date: 2026-11-08

## Context

Copying must use exactly the plan the operator approved, reject source changes after inventory, remain retryable after partial failure, and never promote failed work as the successful baseline.

## Decision

Apply requires the 64-character approved plan identifier and revalidates every plan fingerprint. It performs a complete metadata preflight before copying, then rechecks each source item immediately before transfer. Only `Ready` new and modified items are considered. Missing, review, and blocked items are never transferred or deleted.

Each run records tokenized results. A failed run leaves the existing `current.json` pointer unchanged. A successful run copies the current inventory into versioned state storage and atomically replaces the pointer. Existing destination files that already match planned length and timestamp are recorded as `AlreadyCurrent`, enabling safe retry after partial failure.

## Consequences

- The plan now includes source length and UTC modification ticks for pre-copy validation.
- A content change that preserves both length and timestamp is not detected in version 1.
- Partial file copies may exist after failure, but the baseline is not promoted and retry reconciles them.
- State storage retains versioned inventories and requires a later retention policy.
- Version 1 copies data and timestamps; it does not copy ACLs or delete destination content.
