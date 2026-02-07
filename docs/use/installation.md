---
title: Installation
sidebar_label: Installation
---

# Installation

IdLE can be consumed either from the **PowerShell Gallery** (recommended for most users) or directly from the
**Github repository source** (useful for contributors and development scenarios).

---

## Requirements

- PowerShell **7.x** or later (`pwsh`)

---

## Install IdLE

### Install from PowerShell Gallery (recommended)

From a PowerShell 7 prompt:

```powershell
# Install the IdLE meta-module (automatically installs Core and Steps.Common dependencies)
Install-Module -Name IdLE

# Import the module
Import-Module -Name IdLE
```

The `IdLE` module declares `IdLE.Core` and `IdLE.Steps.Common` as dependencies (`RequiredModules`), so PowerShell automatically installs and imports them when you install `IdLE`.

**Installing optional modules:**

Provider and additional step modules are published as separate modules and can be installed independently:

```powershell
# Install specific provider modules as needed
Install-Module -Name IdLE.Provider.EntraID
Install-Module -Name IdLE.Provider.AD

# Install optional step modules
Install-Module -Name IdLE.Steps.Mailbox
```

Each provider and step module declares its own dependencies, so PowerShell will automatically install required modules (typically `IdLE.Core`).

### Install from repository source

This path is primarily intended for contributors and development scenarios.

From a PowerShell 7 prompt:

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import meta module (automatically bootstraps module discovery for repo layout)
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

**Repository bootstrap behavior:**

When importing `IdLE` from a repository/zip layout, the module automatically adds the `src/` directory to `$env:PSModulePath` (process-scoped only). This enables subsequent name-based imports:

```powershell
# After importing IdLE from source, you can import other modules by name
Import-Module IdLE.Provider.EntraID -Force
Import-Module IdLE.Steps.Mailbox -Force
```

The bootstrap is:
- **Idempotent**: Safe to import multiple times
- **Process-scoped**: No persistent system changes
- **Automatic**: No manual `$env:PSModulePath` configuration required

### Verify installation

```powershell
Get-Module IdLE -ListAvailable | Select-Object Name, Version, Path
Get-Command -Module IdLE
```

---

## What gets imported

### `IdLE` meta-module (baseline)

`IdLE` is the **baseline** entrypoint. It declares `IdLE.Core` and `IdLE.Steps.Common` as dependencies:

- **IdLE.Core** — the workflow engine (step-agnostic)
- **IdLE.Steps.Common** — first-party built-in steps (e.g. `IdLE.Step.EmitEvent`, `IdLE.Step.EnsureAttribute`)

**PowerShell Gallery installation:**
PowerShell automatically installs and imports these dependencies when you `Install-Module IdLE` and `Import-Module IdLE`.

**Repository/zip installation:**
The `IdLE` module automatically loads `IdLE.Core` and `IdLE.Steps.Common` as nested modules and bootstraps `$env:PSModulePath` to enable name-based imports of other modules.

Built-in steps are **available to the engine by default**, but for **PowerShell Gallery installations** step functions are intentionally **not exported into the global session state**. This keeps your PowerShell session clean while still allowing workflows to reference built-in steps by `Step.Type`. For **repository/zip installations**, adding `src/` to `$env:PSModulePath` means PowerShell may surface nested module commands in the session; these commands are not considered part of IdLE’s stable public API surface and are primarily intended for use by workflows, not direct interactive invocation.

**Non-blocking guarantee:** `Import-Module IdLE` always succeeds on a clean PowerShell 7 environment without any external dependencies (RSAT, AD tools, third-party modules, etc.).

### Optional modules

Provider and additional step modules are **published separately** and can be installed/imported as needed. These modules may have system-specific or tool-specific dependencies:

- **Provider modules**: `IdLE.Provider.AD`, `IdLE.Provider.EntraID`, `IdLE.Provider.ExchangeOnline`, etc. (see [Provider Reference](providers.md))
- **Optional step modules:** `IdLE.Steps.DirectorySync`, `IdLE.Steps.Mailbox`
- **Development/testing modules:** `IdLE.Provider.Mock`

**From PowerShell Gallery:**

```powershell
# Install and import baseline
Install-Module IdLE
Import-Module IdLE

# Install and import optional provider as needed
Install-Module IdLE.Provider.AD
Import-Module IdLE.Provider.AD
```

**From source:**

```powershell
# Import baseline (automatically bootstraps module discovery)
Import-Module ./src/IdLE/IdLE.psd1 -Force

# Import optional provider by name (works because of bootstrap)
Import-Module IdLE.Provider.AD -Force
```

For usage details, see [Use > Provider](../use/providers.md).

---

## Multi-Module Architecture

Starting with version 1.0, IdLE uses a **multi-module distribution model** where each module is published separately to the PowerShell Gallery:

- **IdLE.Core** — Workflow engine (published separately)
- **IdLE.Steps.Common** — Built-in steps (published separately)
- **IdLE** (meta-module) — Declares `RequiredModules` dependency on Core and Steps.Common
- **IdLE.Provider.\*** — Provider modules (each published separately)
- **IdLE.Steps.\*** — Optional step modules (each published separately)

When you `Install-Module IdLE`, PowerShell automatically installs IdLE.Core and IdLE.Steps.Common as dependencies.

This architecture provides:
- ✅ **Standard PowerShell dependency resolution** via `RequiredModules`
- ✅ **Granular installation** — Install only the modules you need (e.g., `Install-Module IdLE.Provider.EntraID`)
- ✅ **Clear dependency chains** — PowerShell automatically resolves and installs dependencies
- ✅ **Third-party extensibility** — Other modules can declare IdLE modules as dependencies

### Source vs Published Manifests

The repository uses a **dual-manifest strategy** to support both repo/zip and PowerShell Gallery scenarios:

**Repository/Zip Layout:**
- `IdLE` manifest uses `NestedModules` with relative paths
- Includes `ScriptsToProcess` to bootstrap `$env:PSModulePath`
- Enables direct import: `Import-Module ./src/IdLE/IdLE.psd1`

**PowerShell Gallery Published Packages:**
- Packaging tool transforms manifests for publication
- `IdLE` manifest uses name-based `RequiredModules` (no `NestedModules`)
- No `ScriptsToProcess` (not needed in standard module paths)
- Standard PowerShell dependency resolution

This approach ensures:
- ✅ Contributors can work directly from repository source
- ✅ Published modules follow PowerShell best practices
- ✅ No manual `$env:PSModulePath` configuration required for either scenario
