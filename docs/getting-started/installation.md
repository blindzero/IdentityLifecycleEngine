# Installation

IdLE can be consumed either from the **PowerShell Gallery** (recommended for most users) or directly from the
repository source (useful for contributors and development scenarios).

## Install from PowerShell Gallery

From a PowerShell 7 prompt:

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

### Verify install

```powershell
Get-Module IdLE -ListAvailable | Select-Object Name, Version, Path
Get-Command -Module IdLE | Select-Object -First 10
```

> Note: The `IdLE` meta-module loads the bundled nested modules (e.g. `IdLE.Core`, built-in steps, and the mock provider
> used by examples) from within the installed package.

## Install from repository source

This path is primarily intended for contributors.

### Requirements

- PowerShell **7+** (`pwsh`)
- Pester **5+** (for tests)

### Clone and import

From a PowerShell 7 prompt:

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import meta module
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

## Optional step modules

The core engine is step-agnostic. To use built-in steps, import the step module(s) you need:

```powershell
Import-Module ./src/IdLE.Steps.Common/IdLE.Steps.Common.psd1 -Force
```

## Verify install (source)

```powershell
Get-Command -Module IdLE
Get-Command -Module IdLE.Core
```
