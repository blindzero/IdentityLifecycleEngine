# Security Policy

This document describes how to report security vulnerabilities for **IdentityLifecycleEngine (IdLE)** and what
maintainers/consumers can expect in terms of response and disclosure.

> Note: Detailed guidance for maintainers (required repository settings, Dependabot configuration, and operational
> checks) lives in `docs/advanced/security.md`.

## Supported Versions

IdLE is currently in active development.

- **Only the latest released version is considered supported for security fixes.**
- Security fixes are developed on `main` and released as soon as practical.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security-sensitive reports.

Preferred channel:

1. Use **GitHub Security Advisories** to privately report a vulnerability:
   - Repository → **Security** → **Advisories** → **New draft security advisory**

What to include:

- A clear description of the issue and potential impact
- Reproduction steps or a minimal proof-of-concept (if available)
- Affected version(s), configuration, and environment details
- Any suggested fix or mitigation (optional)

If you are unsure whether something is security-relevant, report it anyway via Security Advisories.

## Coordinated Disclosure

Maintainers will:

- Acknowledge receipt as soon as reasonably possible
- Work with the reporter to reproduce and validate the issue
- Prepare a fix and a release plan
- Publish an advisory and release notes once a fix is available

We aim to coordinate disclosure to reduce risk for users while ensuring proper credit for reporters.

## Maintainer Notes

Maintainers should ensure repository security hygiene is enabled and continuously monitored. See:

- `docs/advanced/security.md`
