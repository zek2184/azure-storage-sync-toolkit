# ADR 0002: Deterministic disk-backed inventory

- Status: Accepted
- Date: 2026-11-08

## Context

Migration sources can contain more records than should be retained in memory. Inventories and public demo artifacts must also avoid storing absolute source roots.

## Decision

Inventory records are partitioned into deterministic buckets derived from a case-insensitive SHA-256 path hash. Each record stores a UTF-8/Base64 relative path token, length, UTC modification ticks, and file attributes. Comparison loads one matching bucket pair at a time.

Manifests store generated inventory identifiers, counts, schema information, and the redacted root marker `[SOURCE]`; they do not store absolute source paths. Missing items are labeled candidates and never cause deletion.

## Consequences

- Peak comparison memory is bounded by the largest bucket pair rather than the complete inventory.
- Inventories must use the same bucket count to be compared.
- Version 1 change detection uses size and UTC modification time, not content hashing.
- Base64 is an encoding for robust TSV storage, not encryption or a security boundary.
