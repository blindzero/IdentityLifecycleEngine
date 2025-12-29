# IdentityLifecycleEngine (IdLE) - Installation

IdLE is currently consumed from the repository source.

## Requirements

- PowerShell **7+** (`pwsh`)
- Pester **5+** (for tests)

## Clone and import

From a PowerShell 7 prompt:

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

Import-Module ./src/IdLE/IdLE.psd1 -Force
```

## Optional step modules

The core engine is step-agnostic. To use built-in steps, import the step module(s) you need:

```powershell
Import-Module ./src/IdLE.Steps.Common/IdLE.Steps.Common.psd1 -Force
```

## Verify install

```powershell
Get-Command -Module IdLE
Get-Command -Module IdLE.Core
```
