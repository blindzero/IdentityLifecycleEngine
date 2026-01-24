# Examples

This folder contains runnable examples for IdLE, organized into categories based on their requirements and intended use.

## Workflow Categories

### Mock
Workflows that run out-of-the-box with `IdLE.Provider.Mock`. These are fully functional demonstrations requiring no external systems.

**Prerequisites:**
- `IdLE` + `IdLE.Steps.Common`
- `IdLE.Provider.Mock`

**Workflows:**
- `joiner-minimal.psd1` — minimal workflow with a single EmitEvent step
- `joiner-minimal-ensureattribute.psd1` — demonstrates EnsureAttribute step
- `joiner-ensureentitlement.psd1` — demonstrates EnsureEntitlement step for group assignment
- `joiner-with-condition.psd1` — demonstrates conditional step execution
- `joiner-with-onfailure.psd1` — demonstrates OnFailureSteps for cleanup and notifications

### Live
Example workflows that require real providers and external systems (Active Directory, Entra ID, Entra Connect). These are intended as templates for production scenarios but cannot run without the necessary infrastructure.

**Prerequisites:**
- Real AD/Entra ID environment
- Provider modules: `IdLE.Provider.ActiveDirectory`, `IdLE.Provider.EntraID`, `IdLE.Provider.DirectorySync.EntraConnect`
- Appropriate authentication/credentials

**Workflows:**
- `ad-joiner-complete.psd1` — complete Active Directory joiner workflow
- `ad-mover-department-change.psd1` — Active Directory department change workflow
- `ad-leaver-offboarding.psd1` — Active Directory leaver offboarding workflow
- `entraid-joiner-complete.psd1` — complete Entra ID joiner workflow
- `entraid-mover-department-change.psd1` — Entra ID department change workflow
- `entraid-leaver-offboarding.psd1` — Entra ID leaver offboarding workflow
- `joiner-with-entraid-sync.psd1` — demonstrates cross-system workflow with AD and Entra ID sync

### Templates
Generic starting points for building custom workflows. These are structurally valid but not executed in CI.

(Currently empty - reserved for future templates)

## Run the demo

From the repository root:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1
```

By default, the demo runs **Mock** workflows only (deterministic, no external dependencies).

### List available workflows

```powershell
# List Mock workflows (default)
.\examples\Invoke-IdleDemo.ps1 -List

# List Live workflows
.\examples\Invoke-IdleDemo.ps1 -List -Category Live

# List all workflows
.\examples\Invoke-IdleDemo.ps1 -List -Category All
```

### Run specific workflows

```powershell
# Run specific Mock workflow by name
.\examples\Invoke-IdleDemo.ps1 -Example joiner-minimal

# Run all Mock workflows (default category)
.\examples\Invoke-IdleDemo.ps1 -All

# Run all workflows in a specific category
.\examples\Invoke-IdleDemo.ps1 -All -Category Live
```

**Note:** The demo script defaults to Mock workflows which work out-of-the-box. Live workflows can be executed via the demo script, but will fail if the required providers and infrastructure are not available. To run Live workflows, you must modify the demo script to provide the necessary real providers (see lines 246-248 in `Invoke-IdleDemo.ps1`).

### Interactive selection

If you run the script without parameters, it will interactively prompt you to select from available Mock workflows.

## How it works

The demo:

- validates the workflow using `Test-IdleWorkflow`
- builds a plan from the workflow (`.psd1`) using `New-IdlePlan`
- executes the plan using `Invoke-IdlePlan` with mock or real providers
- prints step results and buffered events

## Workflow structure

Workflows are **data-only** PSD1 files. A minimal workflow looks like:

```powershell
@{
  Name           = 'Joiner - Minimal Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'EmitHello'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Hello from workflow.' }
    }
  )
}
```

For details, see `docs/usage/workflows.md`.

## Events

IdLE buffers all emitted events in the execution result:

```powershell
$result.Events | Select-Object Type, StepName, Message
```

Hosts can optionally stream events live by providing `-EventSink` as an object implementing `WriteEvent(event)`.

## Workflow Matrix

| Workflow File | Category | Runnable with Mock | Required Providers | External Prerequisites |
|---------------|----------|--------------------|--------------------|------------------------|
| joiner-minimal.psd1 | Mock | ✅ Yes | Identity (Mock) | None |
| joiner-minimal-ensureattribute.psd1 | Mock | ✅ Yes | Identity (Mock) | None |
| joiner-ensureentitlement.psd1 | Mock | ✅ Yes | Identity (Mock) | None |
| joiner-with-condition.psd1 | Mock | ✅ Yes | Identity (Mock) | None |
| joiner-with-onfailure.psd1 | Mock | ✅ Yes | Identity (Mock) | None |
| ad-joiner-complete.psd1 | Live | ❌ No | Identity (AD) | Active Directory, credentials |
| ad-mover-department-change.psd1 | Live | ❌ No | Identity (AD) | Active Directory, credentials |
| ad-leaver-offboarding.psd1 | Live | ❌ No | Identity (AD) | Active Directory, credentials |
| entraid-joiner-complete.psd1 | Live | ❌ No | Identity (Entra ID) | Entra ID, credentials |
| entraid-mover-department-change.psd1 | Live | ❌ No | Identity (Entra ID) | Entra ID, credentials |
| entraid-leaver-offboarding.psd1 | Live | ❌ No | Identity (Entra ID) | Entra ID, credentials |
| joiner-with-entraid-sync.psd1 | Live | ❌ No | Identity (AD), Cloud (Entra ID), DirectorySync | AD, Entra ID, Entra Connect, credentials |
