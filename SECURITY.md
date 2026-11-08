# Security policy

## Supported versions

The project is pre-release. Security fixes apply to the current main development line until a stable release policy is published.

## Reporting a vulnerability

Do not open a public issue containing credentials, private paths, personal data, or exploit details. When the repository is published, use GitHub's private vulnerability reporting or a private security advisory. Until then, report concerns directly to the repository owner through an established private channel.

## Secrets and sensitive data

- Configuration files containing environment-specific values must use the ignored `*.local.psd1` suffix.
- Credentials must come from an external credential provider or process environment designed for secrets; they must not be stored in toolkit configuration.
- Generated reports must redact absolute roots by default.
- Test fixtures and screenshots must be generated from the documented synthetic dataset.

## Security boundaries

Version 1 is a non-destructive migration-support tool, not a backup product or access-control migration system. It will not delete source data, mirror deletions, rename source items, or reproduce source ACLs.

