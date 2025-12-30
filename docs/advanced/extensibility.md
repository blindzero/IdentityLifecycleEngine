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

A new provider typically involves:

1. A contract interface (if not already present)
2. A provider implementation module
3. Session acquisition via host execution context
4. Contract tests and unit tests

## Versioning strategy

Keep workflows stable by treating step identifiers as contracts.
If behavior changes incompatibly:

- introduce a new step id or explicit handler mapping
- keep the old step id available for older workflows

## Keep the core headless

Do not add:

- interactive prompts
- authentication code inside steps
- UI or web server dependencies

Those belong in a host application.

## Register step handlers

Steps are executed via a host-provided step registry.

- Workflows reference steps by `Type` (identifier).
- The host maps this identifier to a **function name** (string) in the step registry.

ScriptBlock handlers are intentionally not supported as a secure default.
