# Development instructions

Use a scaled SDLC: confirm requirements and acceptance criteria, document design decisions, implement in milestones, test success and failure paths, review privacy and security, and publish only after explicit approval.

## Clean-room boundary

- Do not copy code, reports, screenshots, metrics, paths, configuration, names, or Git history from an existing private repository.
- Use generated synthetic data in tests, demonstrations, reports, and screenshots.
- Never commit credentials, signed URLs, connection strings, tenant identifiers, access keys, or client information.

## Engineering conventions

- Maintain Windows PowerShell 5.1 compatibility for the version 1 filesystem provider.
- Use approved PowerShell verbs, strict mode, explicit validation, and terminating errors at public boundaries.
- Keep configuration, inventory, comparison, policy, transfer, state, reporting, and demo generation separated.
- Default to preview and reject delete, mirror, move, rename, purge, and ACL-copy behavior.
- Add regression coverage for fixes when practical.
- Keep documentation claims reproducible through a test or synthetic demonstration.

## Definition of done

Acceptance criteria pass, quality checks are recorded, documentation matches behavior, public artifacts pass privacy review, and publication has explicit approval.

