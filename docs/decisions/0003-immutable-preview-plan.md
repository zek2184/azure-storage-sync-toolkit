# ADR 0003: Immutable policy-evaluated preview plans

- Status: Accepted
- Date: 2026-11-08

## Context

An operator must be able to review exactly what a later apply operation would use. A plan must become invalid if its delta, current inventory, policy, plan items, or preview CSV changes.

## Decision

The preview layer evaluates new and modified items against a normalized safety policy. Items are classified as `Ready`, `Review`, or `Blocked`. Review and blocked items are not eligible for transfer. Missing items are written as `EvidenceOnly` with `NO_DELETE_ACTION`.

The plan identifier is a SHA-256 digest bound to the delta identifier, current inventory identifier, normalized policy fingerprint, plan-items fingerprint, and preview-CSV fingerprint. Validation recomputes every fingerprint before an apply operation may trust the plan.

## Consequences

- Editing a generated plan or CSV invalidates the plan identifier.
- A plan cannot be reused with a different current inventory or delta.
- Relative paths appear in the operator CSV, but absolute source roots do not.
- CSV values beginning with spreadsheet formula characters are prefixed with an apostrophe.
- Review-item approval is deferred to the apply milestone; review items remain non-transferable in this milestone.
