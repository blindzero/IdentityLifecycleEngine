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

- **Joiner / Mover / Leaver** orchestration (and custom scenarios)
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

## Quickstart

Typical flow: **Create request → Validate workflow → Build plan → Execute plan**

```powershell
# 1) Create a request (scenario + identity keys + desired state)
$request = New-IdleLifecycleRequest -Scenario Joiner -Actor 'alice@contoso.com' -CorrelationId (New-Guid) -IdentityKeys @{
  EmployeeId = '12345'
  UPN        = 'new.user@contoso.com'
} -DesiredState @{
  Attributes = @{
    Department = 'IT'
    Title      = 'Engineer'
  }
  Entitlements = @(
    @{ Type = 'Group'; Value = 'APP-CRM-Users' }
    @{ Type = 'License'; Value = 'M365_E3' }
  )
}

# 2) Validate configuration/workflow compatibility
Test-IdleWorkflow -WorkflowPath ./workflows/joiner.psd1 -Request $request

# 3) Build a plan (preview actions and warnings)
$plan = New-IdlePlan -WorkflowPath ./workflows/joiner.psd1 -Request $request -Providers $providers

# Optional: inspect the plan
$plan.Actions | Format-Table

# 4) Execute the plan
Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## Workflow Definitions (concept)

Workflows are configuration-first (e.g., `.psd1`) and describe:

- step sequence
- conditions (declarative, not arbitrary PowerShell expressions)
- required inputs / produced outputs

Example (illustrative):

```powershell
@{
  Name     = 'Joiner - Standard'
  Scenario = 'Joiner'
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

PRs welcome. A few guiding principles:

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
