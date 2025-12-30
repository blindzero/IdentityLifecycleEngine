# Providers

Providers are the system-specific adapters (for example: Active Directory, Entra ID, Exchange Online).

The engine core talks only to provider contracts.

## Responsibilities

Providers typically:

- authenticate and manage sessions
- translate generic operations to system APIs
- are mockable for tests
- avoid global state

Steps should not handle authentication.

## Acquire sessions via host

Providers can acquire sessions through a host-provided execution context callback:

- the host may allow interactive auth (or disallow it in CI)
- the host may cache sessions
- the provider declares requirements and asks for a session

This keeps IdLE.Core headless while supporting real-world auth flows.

## Testing providers

Providers should have contract tests that verify behavior against a mock or test harness.
Unit tests must not call live systems.

## Related

- [Testing](../advanced/testing.md)
- [Architecture](../advanced/architecture.md)

## Trust and security

Providers and the step registry are host-controlled extension points and should be treated as trusted code.
Workflows and lifecycle requests are data-only and must not contain executable objects.

For details, see `docs/advanced/security.md`.
