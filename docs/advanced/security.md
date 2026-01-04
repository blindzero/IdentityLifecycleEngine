# Security and Trust Boundaries

IdLE is designed to execute *data-driven* lifecycle workflows in a deterministic way.

Because IdLE is an orchestration engine, it must be very explicit about **what is trusted** and **what is untrusted**.

## Trust boundaries

### Untrusted inputs (data-only)

These inputs may come from users, CI pipelines, or external systems and **must be treated as untrusted**:

- Workflow definitions (PSD1)
- Lifecycle requests (input objects)
- Step parameters (`With`, `When`)

**Rule:** Untrusted inputs must be *data-only*. They must not contain ScriptBlocks or other executable objects.

IdLE enforces this by rejecting ScriptBlocks when importing workflow definitions and by validating inputs at runtime.

### Trusted extension points (code)

These inputs are provided by the host and are **privileged** because they determine what code is executed:

- Step registry (maps `Step.Type` to a handler function name)
- Provider modules / provider objects (system-specific adapters)
- External event sinks (streaming events)

**Rule:** Only trusted code should populate these extension points.

## Secure defaults

IdLE applies secure defaults to reduce accidental code execution:

- Workflow configuration is loaded as data and ScriptBlocks are rejected.
- Event streaming uses an object-based contract (`WriteEvent(event)`); ScriptBlock event sinks are rejected.
- Step registry handlers must be function names (strings); ScriptBlock handlers are rejected.

## Guidance for hosts

- Keep workflow files in a protected location and review them like code (even though they are data-only).
- Load step and provider modules explicitly before execution.
- Treat the step registry as privileged configuration and do not let workflow authors change it.
- If you stream events, implement a small sink object with a `WriteEvent(event)` method and keep it side-effect free.

## Guidance for step authors

- Use providers for system operations; do not embed authentication logic inside steps.
- Emit events using `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`.
- Avoid global state. Steps should be idempotent whenever possible.
