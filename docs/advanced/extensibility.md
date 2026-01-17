# Extensibility

IdLE is designed for change through modules instead of forks.

## Add a new step

A new step typically involves:

1. A metadata definition (what inputs and outputs are allowed)
2. A planning function (test) that produces data-only actions
3. An execution function (invoke) that performs actions via providers
4. Unit tests (Pester)

Steps can emit structured events using the execution context contract:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`

Keep steps host-agnostic: do not call UI APIs directly.

## Add a new provider

Providers are responsible for interacting with external systems (directories,
cloud services, APIs, etc.).

A new provider typically involves:

1. A contract interface (if not already present)
2. A provider implementation module
3. Auth session acquisition via host execution context (AuthSessionBroker)
4. Contract tests and unit tests

### Auth session acquisition (AuthSessionBroker)

IdLE keeps authentication out of the core engine. Hosts provide an auth session broker
that is responsible for obtaining and caching authenticated runtime handles (tokens,
Graph clients, Exchange Online sessions, LDAP binds, etc.).

- Hosts MUST pass the broker via `Providers.AuthSessionBroker`.
- Providers SHOULD acquire sessions through the execution context:
  - `Context.AcquireAuthSession(Name, Options)`

Broker contract:

- The broker MUST expose an `AcquireAuthSession(Name, Options)` method.
- `Name` is a routing key (for example: `MicrosoftGraph`, `ExchangeOnline`, `ActiveDirectory`).
- `Options` is optional (`$null` is treated as an empty hashtable) and must be data-only:
  - ScriptBlock values are rejected, including nested values.
- The engine enriches options with `CorrelationId` and `Actor` when available.
- The engine deep-copies `Options` before invoking the broker; brokers MUST treat
  options as immutable and MUST NOT mutate nested values.

Security notes:

- Do not embed credentials directly in `Options`.
- Treat `Options` as configuration input, not a secret store.
- Use host secret management and keep secrets out of plans, events, and exports.

### Capability Advertisement

Providers must explicitly advertise their supported capabilities via a
`GetCapabilities()` method. These capabilities are used by the engine
during plan build to validate whether all required functionality is
available.

The full contract, naming rules, and validation behavior are described in
[Provider Capabilities](provider-capabilities.md).

Providers should include the corresponding provider capability contract tests
to ensure compliance.

## Versioning strategy

Keep workflows stable by treating step identifiers as contracts.
If behavior changes incompatibly:

- introduce a new step id or explicit handler mapping
- keep the old step id available for older workflows

## Keep the core headless

Do not add:

- interactive prompts
- authentication code inside steps
- authentication flows inside providers (use AuthSessionBroker)
- UI or web server dependencies

Those belong in a host application.

## Register step handlers

Steps are executed via a host-provided step registry.

- Workflows reference steps by `Type` (identifier).
- The host maps this identifier to a **function name** (string) in the step registry.

ScriptBlock handlers are intentionally not supported as a secure default.

Step handlers may optionally declare a `Context` parameter.
For backwards compatibility, the engine passes `-Context` only when the handler
supports it.
