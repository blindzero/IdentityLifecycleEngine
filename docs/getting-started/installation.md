# Installation

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

> Note: The `IdLE` module automatically imports the baseline modules (`IdLE.Core` and `IdLE.Steps.Common`).
> Optional modules (providers, additional step modules) are shipped with the package but not auto-imported.

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

### Default: `IdLE` meta-module (baseline)

`IdLE` is the **baseline** entrypoint. Importing it automatically loads:

- **IdLE.Core** — the workflow engine (step-agnostic)
- **IdLE.Steps.Common** — first-party built-in steps (e.g. `IdLE.Step.EmitEvent`, `IdLE.Step.EnsureAttribute`)

Built-in steps are **available to the engine by default**, but are intentionally **not exported into the global session state**.
This keeps your PowerShell session clean while still allowing workflows to reference built-in steps by `Step.Type`.

**Non-blocking guarantee:** `Import-Module IdLE` always succeeds on a clean PowerShell 7 environment without any external dependencies (RSAT, AD tools, third-party modules, etc.).

**When to use:** All users and production scenarios.

### Advanced: Engine-only import

Advanced hosts can import the engine without any step packs:

```powershell
Import-Module ./src/IdLE.Core/IdLE.Core.psd1 -Force
```

**When to use:** Custom host implementations that provide their own step registry and providers.

---

## Optional modules (shipped but not auto-imported)

The `IdLE` package ships additional modules that are **not automatically imported**. These modules may have system-specific or tool-specific dependencies and are imported explicitly when needed:

- **Provider modules:** `IdLE.Provider.AD`, `IdLE.Provider.EntraID`, `IdLE.Provider.ExchangeOnline`, `IdLE.Provider.DirectorySync.EntraConnect`
- **Optional step modules:** `IdLE.Steps.DirectorySync`, `IdLE.Steps.Mailbox`
- **Development/testing modules:** `IdLE.Provider.Mock`

Example (from source):

```powershell
# Import baseline (auto-imports Core and Steps.Common)
Import-Module ./src/IdLE/IdLE.psd1 -Force

# Import optional provider when needed
Import-Module ./src/IdLE.Provider.AD/IdLE.Provider.AD.psd1 -Force
```

For a complete list of available providers and usage details, see **[Providers](../usage/providers.md)**.

---

## Next steps

- [Quickstart](quickstart.md) — Run the demo and learn the Plan → Execute flow
- [Providers](../usage/providers.md) — Learn about provider aliases and usage
- [Workflows](../usage/workflows.md) — Learn how to define workflows
