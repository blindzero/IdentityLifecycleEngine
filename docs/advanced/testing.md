# Testing

IdLE is designed to be testable in isolation.

## Unit tests

Unit tests should:

- use Pester
- use mock providers
- avoid live system calls

## Provider contract tests

Provider contract tests verify that an implementation matches the expected contract.
They can run against:

- a mock harness
- a local test double
- a dedicated test tenant (only when explicitly intended)

## Workflow validation in CI

Validate workflows and step metadata in CI using a dedicated validation command.

Principles:

- fail fast for unknown keys
- fail early for invalid references
- keep configuration data-only (no script blocks)

## Tips

- Prefer deterministic input fixtures
- Keep tests readable and focused
- Treat public cmdlets as stable contracts
