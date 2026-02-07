---
title: Migration Guide v0.10
sidebar_label: Migration v0.10
---

# Migration Guide: v0.9 → v0.10

This guide describes breaking changes introduced in IdLE v0.10 and how to adapt existing code.

## Step Infrastructure Refactor

**Summary**: Generic step infrastructure has been moved from `IdLE.Steps.Common` to `IdLE.Core`.

### What Changed

In v0.9 and earlier:
- `IdLE.Steps.Common` contained both step infrastructure (helpers, metadata) and step implementations
- Step packs could depend solely on `IdLE.Steps.Common`

In v0.10+:
- `IdLE.Core` contains all generic step infrastructure:
  - `Get-IdleStepMetadataCatalog` (exported from Core)
  - `Invoke-IdleProviderMethod` (now public, exported from Core)
  - `Test-IdleProviderMethodParameter` (now public, exported from Core)
- `IdLE.Steps.Common` contains only step implementations
- Each step pack (including `IdLE.Steps.Common`) has its own `Get-IdleStepMetadataCatalog` for the steps it implements

### Impact on Step Pack Authors

**Before v0.10:**
```powershell
# In MyStepPack.psd1
@{
    RequiredModules = @('IdLE.Steps.Common')
    # ...
}
```

**After v0.10:**
```powershell
# In MyStepPack.psd1
@{
    RequiredModules = @('IdLE.Core', 'IdLE.Steps.Common')  # Add IdLE.Core
    # ...
}
```

**If your step pack uses `Invoke-IdleProviderMethod`:**
- No code changes required
- Function is now exported from `IdLE.Core` and available to all step packs

**If your step pack provides custom step types:**
- Implement `Get-IdleStepMetadataCatalog` in your step pack
- Return a hashtable mapping your step types to their metadata

### Impact on Hosts

**For hosts that import the IdLE meta-module:**
- No changes required
- `IdLE` meta-module automatically loads `IdLE.Core` and `IdLE.Steps.Common`

**For hosts that directly import individual modules:**
- Ensure `IdLE.Core` is loaded before step packs
- Order: `IdLE.Core` → `IdLE.Steps.Common` → Other step packs

### New Public API in IdLE.Core

The following functions are now **public** and exported from `IdLE.Core`:

#### `Get-IdleStepMetadataCatalog`
Returns the metadata catalog for common step types. Previously only in `IdLE.Steps.Common`.

**Note**: Each step pack module should implement its own `Get-IdleStepMetadataCatalog` that returns metadata for the steps in that pack.

#### `Invoke-IdleProviderMethod`
Foundational helper for invoking provider methods with auth session support.

**Usage:**
```powershell
$result = Invoke-IdleProviderMethod `
    -Context $Context `
    -With @{ AuthSessionName = 'ProviderName' } `
    -ProviderAlias 'ProviderName' `
    -MethodName 'SomeMethod' `
    -MethodArguments @($arg1, $arg2)
```

#### `Test-IdleProviderMethodParameter`
Tests whether a provider method accepts a specific parameter (used for backwards compatibility detection).

**Usage:**
```powershell
$method = $provider.PSObject.Methods['MyMethod']
$supportsAuth = Test-IdleProviderMethodParameter -ProviderMethod $method -ParameterName 'AuthSession'
```

### Rationale

This refactor establishes a clearer architectural layering:

- **IdLE.Core**: Engine foundations and step infrastructure (required by all step packs)
- **IdLE.Steps.Common**: Reusable step implementations (optional, use when needed)
- **Other step packs**: Domain-specific step implementations

Benefits:
- Clear separation of concerns
- Reduced coupling between step packs
- Third-party step packs can depend solely on `IdLE.Core`
- Easier to reason about module dependencies

## Questions or Issues?

If you encounter issues migrating to v0.10, please file an issue on GitHub.
