# Security and Trust Boundaries

IdLE is designed to execute **data-driven** identity lifecycle workflows in a deterministic way.

Because IdLE is an orchestration engine, it must be explicit about **what is trusted** and **what is untrusted**.

## Trust boundaries

### Untrusted inputs (data-only)

These inputs may come from users, CI pipelines, or external systems and **must be treated as untrusted**:

- Workflow definitions (PSD1)
- Lifecycle requests (input objects)
- Step parameters (`With`, `When`)
- Provider configuration maps (e.g., `Providers` passed into plan execution)
- Event payloads (`Event.Data`) emitted by steps/providers

**Rule:** Untrusted inputs must be *data-only*. They must not contain ScriptBlocks or other executable objects.

IdLE enforces this by rejecting ScriptBlocks when importing workflow definitions and by validating inputs at runtime.

IdLE assumes these inputs are **data only**. Dynamic / executable content must be rejected.

Current enforcement principles:

- Workflow definitions must be static data structures (hashtables/arrays/strings/numbers/bools).
- ScriptBlocks inside workflow definitions are rejected.
- Event sinks must be objects with a `WriteEvent(event)` method. ScriptBlock sinks are rejected.
- Step registry handlers must be **function names (strings)**. ScriptBlock handlers are rejected.

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

## Redaction at output boundaries

IdLE treats certain surfaces as **output boundaries**. Before data crosses these boundaries, IdLE creates a **redacted copy** of structured objects to reduce the risk of leaking secrets into logs, exports, or host systems.

### What gets redacted

IdLE replaces sensitive values with the placeholder string:

- `[REDACTED]`

Redaction happens for:

- **Known secret keys** (case-insensitive, exact match):
  - `password`, `passphrase`, `secret`, `token`
  - `apikey`, `apiKey`, `clientSecret`
  - `accessToken`, `refreshToken`
  - `credential`, `privateKey`
- **Sensitive runtime types**, regardless of key name:
  - `PSCredential`
  - `SecureString`

### Where redaction is applied

Redaction is applied **before** data is:

- Buffered as run events (execution result `Events`)
- Sent to external event sinks
- Exported as plan JSON (`request.input`, `step.inputs`, `step.expectedState`)
- Returned in execution results (`Providers`)

### Non-goals

- IdLE does **not** attempt to redact secrets embedded inside free-text message strings (e.g., `Event.Message`).
  - Steps and providers should avoid placing secrets into free-text messages.

### Rationale

Redaction is intentionally centralized at output boundaries to keep the execution model unchanged and to avoid altering step/provider behavior while making outputs safe-by-default.

## Guidance for hosts

- Keep workflow files in a protected location and review them like code (even though they are data-only).
- Load step and provider modules explicitly before execution.
- Treat the step registry as privileged configuration and do not let workflow authors change it.
- If you stream events, implement a small sink object with a `WriteEvent(event)` method and keep it side-effect free.

## Guidance for step authors

- Use providers for system operations; do not embed authentication logic inside steps.
- Emit events using `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`.
- Avoid global state. Steps should be idempotent whenever possible.

## Repository security hygiene (maintainers)

This section documents the repository-level security posture and the settings maintainers should keep enabled.

### Dependency hygiene (Dependabot)

IdLE uses Dependabot to keep GitHub Actions dependencies current.

- Configuration file: `.github/dependabot.yml`
- Expected behaviour: a **weekly** PR that groups GitHub Actions updates

**Verify**:

1. Repository → **Insights** → **Dependency graph** → **Dependabot**
2. Confirm update activity and that PRs are being opened

### Recommended GitHub repository security settings

These settings are managed in GitHub and cannot be enforced via source control. Maintain them as part of routine repo maintenance:

- **Dependabot alerts**: enabled
- **Dependabot security updates**: enabled
- **Secret scanning**: enabled (and **push protection** if available for the repo)
- **Branch protection rules** on `main`:
  - Require pull requests before merging
  - Require status checks to pass before merging (CI)
  - Restrict force pushes
- **Least privilege** for workflows:
  - Use explicit `permissions:` blocks in workflows
  - Prefer read-only defaults unless a job needs write access

**Verify** (typical locations):

- Repository → **Settings** → **Security** (feature availability depends on GitHub plan)
- Repository → **Settings** → **Branches** (branch protection)

## See also

- Root security policy: `SECURITY.md`
