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
# Install the IdLE meta-module (pulls IdLE.Core and IdLE.Steps.Common as dependencies)
Install-Module -Name IdLE -Scope CurrentUser

# Import the baseline modules
Import-Module -Name IdLE
```

:::info Command collision during install?
If PowerShellGet reports that a command is already available, prefer a clean reinstall instead of `-AllowClobber`.

```powershell
Get-InstalledModule IdLE, IdLE.Core, IdLE.Steps.Common -ErrorAction SilentlyContinue |
  Uninstall-Module -AllVersions -Force

Install-Module -Name IdLE -Scope CurrentUser -Force
Import-Module -Name IdLE
```
:::

---

## Install optional modules

Providers and additional step modules are published as separate modules and can be installed independently.

```powershell
# Provider modules (examples)
Install-Module -Name IdLE.Provider.AD -Scope CurrentUser
Install-Module -Name IdLE.Provider.EntraID -Scope CurrentUser
Install-Module -Name IdLE.Provider.ExchangeOnline -Scope CurrentUser

# Optional step modules (examples)
Install-Module -Name IdLE.Steps.Mailbox -Scope CurrentUser

# Mock provider (safe, used for tests and walkthroughs)
Install-Module -Name IdLE.Provider.Mock -Scope CurrentUser
```

Import only what you need:

```powershell
Import-Module -Name IdLE.Provider.Mock
Import-Module -Name IdLE.Provider.AD
```

:::tip
If a workflow references a StepType from an optional steps module, that steps module must be installed and imported in the host session.
:::

---

## Install from repository source (contributors)

This path is intended for development and contribution scenarios.

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import meta module (bootstraps module discovery for repo layout)
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

After importing from source, you can import additional modules by name:

```powershell
Import-Module IdLE.Provider.Mock -Force
Import-Module IdLE.Steps.Mailbox -Force
```

---

## Verify installation

```powershell
Get-Module IdLE -ListAvailable | Select-Object Name, Version, Path
Get-Command -Module IdLE | Sort-Object Name
```

---

## Next

- Run your first end-to-end example: [Quick Start](quickstart.md)
- Follow the guided path: [Walkthrough: 1. Workflow Definition](walkthrough/01-workflow-definition.md)
