# IdentityLifecycleEngine (IdLE)

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue)](#requirements)
[![Pester](https://img.shields.io/badge/Tests-Pester%205-blueviolet)](#testing)
[![License](https://img.shields.io/badge/License-See%20LICENSE-lightgrey)](LICENSE.md)

**IdLE** is a **generic, headless, configurable Identity or Account Lifecycle / JML (Joiner–Mover–Leaver) orchestration engine** built for **PowerShell**.

It helps you standardize identity lifecycle processes across environments by separating:

- **what** should happen (workflow definition)
- from **how** it happens (providers/adapters)

---

## Why IdLE?

Identity lifecycle automation tends to become:

- tightly coupled to one system or one environment
- hard to test
- hard to change (logic baked into scripts)

IdLE aims to be:

- **portable** (run anywhere PowerShell 7 runs)
- **modular** (steps + providers are swappable)
- **testable** (Pester-friendly; mock providers)
- **configuration-driven** (workflows as data)

---

## Features

- **Joiner / Mover / Leaver** orchestration (and custom life cycle events)
- **Plan → Execute** flow (preview actions before applying them)
- **Plugin step model** (`Test` / `Invoke`, optional `Rollback` later)
- **Provider/Adapter pattern** (directory, SaaS, REST, file/mock…)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)
- **Idempotent execution** (steps can be written to converge state)

---

## Requirements

- PowerShell **7.x** (`pwsh`)
- Pester **5.x** (for tests)

---

## Installation

### Option A — Clone & import locally (current)

```powershell
git clone [https://github.com/blindzero/IdentityLifecycleEngine](https://github.com/blindzero/IdentityLifecycleEngine)
cd IdentityLifecycleEngine

Import-Module ./src/IdLE/IdLE.psd1 -Force
```

### Option B — PowerShell Gallery (planned)

Once published:

```powershell
Install-Module IdLE
```

---

## Quickstart (Plan → Execute)

IdLE separates **planning** from **execution**:

1. Create a `LifecycleRequest`
2. Build a deterministic `Plan` from a workflow definition (PSD1)
3. Execute the plan with a host-provided step registry (handlers)

> Note: Workflows are **data-only**. Step implementations are provided by the host via the Step Registry.

### Optional built-in steps

IdLE is an engine-only module. Built-in step implementations are provided via optional step modules.

To use the common built-in steps:

```powershell
Import-Module IdLE
Import-Module IdLE.Steps.Common
```

### Example

```powershell
Import-Module .\src\IdLE\IdLE.psd1 -Force

# 1) Request
$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'demo-user'

# 2) Plan
$plan = New-IdlePlan -WorkflowPath .\examples\workflows\joiner-minimal.psd1 -Request $request

# 3) Step registry (host configuration)
$emitHandler = {
    param($Context, $Step)

    & $Context.WriteEvent 'Custom' 'Hello from handler.' $Step.Name @{ StepType = $Step.Type }

    [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Error      = $null
    }
}

$providers = @{
    StepRegistry = @{
        'IdLE.Step.EmitEvent' = $emitHandler
    }
}

# Execute
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
$result.Status
$result.Events | Format-Table TimestampUtc, Type, StepName, Message -AutoSize
```

### Declarative `When` conditions (data-only)

Steps can be conditionally skipped using a declarative `When` block:

```powershell
When = @{
  Path   = 'Plan.LifecycleEvent'
  Equals = 'Joiner'
}
```

If the condition is not met, the step result status becomes `Skipped` and a `StepSkipped` event is emitted.

### More examples

See the runnable demo in `examples/run-demo.ps1` and additional workflow samples in `examples/workflows/`.

## Workflow Definitions (concept)

Workflows are configuration-first (e.g., `.psd1`) and describe:

- step sequence
- conditions (declarative, not arbitrary PowerShell expressions)
- required inputs / produced outputs

Example (illustrative):

```powershell
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps    = @(
    @{ Name = 'ResolveIdentity';    Type = 'IdLE.Step.ResolveIdentity' }
    @{ Name = 'EnsureAttributes';   Type = 'IdLE.Step.EnsureAttributes' }
    @{ Name = 'EnsureEntitlements'; Type = 'IdLE.Step.EnsureEntitlements' }
    @{ Name = 'Finalize';           Type = 'IdLE.Step.EmitSummary' }
  )
}
```

---

## Providers & Steps

IdLE deliberately does not hardcode system access. Instead, it calls provider interfaces/ports.

- **Steps**: reusable building blocks (e.g., ensure attribute, ensure entitlement, disable identity)
- **Providers**: concrete implementations (e.g., Entra ID, AD DS, REST API, file/mock)

This keeps workflows stable even when the underlying systems change.

---

## Event Stream / Auditing

Every run emits structured events (progress, audit, warnings, errors), typically including:

- `CorrelationId`
- `Actor`
- step name / outcome
- change summaries (plan diffs, applied actions)

This enables integration into logging systems, SIEM, ticketing, or custom dashboards.

---

## Testing

Run the full test suite:

```powershell
Invoke-Pester -Path ./tests
```

---

## Contributing

PRs welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md)

- Keep the core **host-agnostic**
- Prefer **configuration** over hardcoding logic
- Aim for **idempotent** steps
- Keep **in-code comments/docs in English**

---

## Roadmap (indicative)

- [ ] Publish `IdLE.Core` to PowerShell Gallery
- [ ] First “batteries included” step pack (`IdLE.Steps.Common`)
- [ ] Reference providers (Mock/File + one real-world provider)
- [ ] Plan diff formatting improvements
- [ ] Rollback support (optional per step)

---

## License

See the [LICENSE.md](LICENSE.md) file.
