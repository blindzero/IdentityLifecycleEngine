---
title: Installation
sidebar_label: Installation
---

IdLE can be installed either from the **PowerShell Gallery** (recommended) or directly from the [**GitHub repository source**](https://github.com/blindzero/IdentityLifecycleEngine) (useful for contributors and development scenarios).

---

## Requirements

- PowerShell **7.x** or later (`pwsh`)

---

## Install from PowerShell Gallery (recommended)

From a PowerShell 7 prompt:

```powershell
# Install IdLE (one package: engine, all built-in steps and all providers)
Install-Module -Name IdLE -Scope CurrentUser

# Import IdLE
Import-Module -Name IdLE
```

The `IdLE` package contains all first-party modules as nested modules, in one synchronized version:

| Module | Content |
| --- | --- |
| `IdLE.Core` | Workflow engine |
| `IdLE.Steps.Common`, `IdLE.Steps.DirectorySync`, `IdLE.Steps.Mailbox` | Built-in steps |
| `IdLE.Provider.AD`, `IdLE.Provider.EntraID`, `IdLE.Provider.ExchangeOnline`, `IdLE.Provider.DirectorySync.EntraConnect`, `IdLE.Provider.Mock` | Providers |

`Import-Module IdLE` makes all built-in steps available to the engine and exports the provider factory functions
(e.g. `New-IdleADIdentityProvider`, `New-IdleMockIdentityProvider`).
See the [reference](../reference/intro-reference.md) for further details on [Steps](../reference/steps.md) and [Providers](../reference/providers.md).

:::info External dependencies are loaded on use
Providers do not import their external modules (e.g. `ActiveDirectory`, `ExchangeOnlineManagement`, `ADSync`) when IdLE is imported.
Install those modules only for the providers you use; they are required when the provider is created or used.
:::

:::info Command collision during install?
If PowerShellGet reports that a command is already available, prefer a clean reinstall instead of `-AllowClobber`.

```powershell
Get-InstalledModule IdLE -ErrorAction SilentlyContinue |
  Uninstall-Module -AllVersions -Force

Install-Module -Name IdLE -Scope CurrentUser -Force
Import-Module -Name IdLE
```

:::

---

---

## Install from repository source

:::info
This installation method is primarily for fetching full example files, testing, and contributing.
:::

This path is intended for development and contribution scenarios.

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import IdLE (imports all modules under src/ as nested modules)
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

:::info
Importing from source loads the same set of modules as the `IdLE` package. Avoid using this in parallel with an IdLE installation from the PowerShell Gallery.
:::

---

## Verify installation

```powershell
Get-Module IdLE -ListAvailable | Select-Object Name, Version, Path
# Public commands (engine cmdlets and provider factories)
Get-Command -Module IdLE | Sort-Object Name
# Bundled modules loaded with IdLE
Get-Module -All -Name 'IdLE.*' | Select-Object Name, Version, ModuleBase
```

---

## Next

- Run your first end-to-end example: [Quick Start](quickstart.md)
- Follow the guided path: [Walkthrough: 1. Workflow Definition](walkthrough/01-workflow-definition.md)
