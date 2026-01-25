# Installation

This is the **single source of truth** for installing and importing IdLE.

IdLE can be consumed either from the **PowerShell Gallery** (recommended for most users) or directly from the
repository source (useful for contributors and development scenarios).

---

## Requirements

- PowerShell **7.x** (`pwsh`)
- Pester **5.7.1+** (for running tests, optional)
- PSScriptAnalyzer **1.24.0+** (for running static analysis, optional)

---

## Install from PowerShell Gallery (recommended)

From a PowerShell 7 prompt:

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

### Verify installation

```powershell
Get-Module IdLE -ListAvailable | Select-Object Name, Version, Path
Get-Command -Module IdLE
```

---

## Install from repository source

This path is primarily intended for contributors and development scenarios.

### Clone and import

From a PowerShell 7 prompt:

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import meta module
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

### Verify installation (source)

```powershell
Get-Command -Module IdLE
Get-Command -Module IdLE.Core
```

---

## What gets imported

### Default: `IdLE` meta-module (batteries included)

`IdLE` is the **batteries-included** entrypoint. Importing it loads:

- **IdLE.Core** — the workflow engine (step-agnostic)
- **IdLE.Steps.Common** — first-party built-in steps (e.g. `IdLE.Step.EmitEvent`, `IdLE.Step.EnsureAttribute`)

Built-in steps are **available to the engine by default**, but are intentionally **not exported into the global session state**.
This keeps your PowerShell session clean while still allowing workflows to reference built-in steps by `Step.Type`.

**When to use:** Most users and production scenarios.

### Advanced: Import built-in steps explicitly

If you want to call step functions directly (e.g. `Invoke-IdleStepEmitEvent`) you can explicitly import the step pack:

```powershell
Import-Module ./src/IdLE.Steps.Common/IdLE.Steps.Common.psd1 -Force
```

**When to use:** Advanced testing, debugging, or building custom step compositions.

### Advanced: Engine-only import

Advanced hosts can import the engine without any step packs:

```powershell
Import-Module ./src/IdLE.Core/IdLE.Core.psd1 -Force
```

**When to use:** Custom host implementations that provide their own step registry and providers.

---

## Provider modules (optional)

The core engine is provider-agnostic. To use provider implementations, install or import the provider modules you need:

### Active Directory Provider

```powershell
# From source
Import-Module ./src/IdLE.Provider.AD/IdLE.Provider.AD.psd1 -Force
```

### Entra ID Provider

```powershell
# From source
Import-Module ./src/IdLE.Provider.EntraID/IdLE.Provider.EntraID.psd1 -Force
```

Provider modules are **not** included in the IdLE meta-module and must be imported separately when needed.

---

## Next steps

- [Quickstart](quickstart.md) — Run the demo and learn the Plan → Execute flow
- [Providers](../usage/providers.md) — Learn about provider aliases and usage
- [Workflows](../usage/workflows.md) — Learn how to define workflows
