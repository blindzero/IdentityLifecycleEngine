# v1.0 Compatibility Policy and Stability Contracts

This document defines the **supported public API surface**, **stable contracts**, and **compatibility guarantees** for IdLE v1.0.0 and beyond.

---

## 1. Supported Public API Surface

### 1.1 Definition

**Supported** = exported + documented + stability-tested.

Only the IdLE meta-module's exported commands are supported. Internal modules (IdLE.Core, IdLE.Steps.*, IdLE.Provider.*) are **unsupported** when imported directly.

### 1.2 Source of Truth

The **sole source of truth** for the supported command surface is:

```
src/IdLE/IdLE.psd1 → FunctionsToExport
```

### 1.3 v1.0 Supported Commands

The minimal supported command set for v1.0:

- `Test-IdleWorkflow`
- `New-IdleLifecycleRequest`
- `New-IdlePlan`
- `Invoke-IdlePlan`
- `Export-IdlePlan`
- `New-IdleAuthSessionBroker`

### 1.4 Enforcement

The supported surface is enforced by **stability tests**:

```powershell
# tests/StabilityContract.Tests.ps1
Describe 'IdLE v1.0 Stability Contract' {
    It 'IdLE exports exactly the v1.0 supported command set' {
        # Validates exact command list - no more, no less
    }
}
```

---

## 2. Internal Modules (Defense-in-Depth)

PowerShell cannot fully prevent direct import of nested modules. IdLE uses a defense-in-depth approach:

### 2.1 Policy (Primary Control)

Only IdLE meta-module exports are supported. Direct imports of internal modules are **unsupported** and may break in any version.

### 2.2 Export Minimization

Internal modules export only what is required for internal composition, not for external consumption.

### 2.3 Import Warning (Recommended)

Internal modules emit a warning when imported directly:

```
WARNING: IdLE.Core is an internal/unsupported module. Import 'IdLE' instead for the supported public API.
To bypass this warning, set IDLE_ALLOW_INTERNAL_IMPORT=1.
```

**Bypass mechanism** (for advanced scenarios only):

```powershell
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'
Import-Module IdLE.Core
```

### 2.4 Security Boundary

Output-boundary redaction rules (credential/secret redaction) must hold regardless of import path.

---

## 3. Stability Contracts

### 3.1 Command Contracts (Supported Cmdlets)

The following are considered **breaking changes** and require a new major version:

- Removing a supported command
- Renaming a supported command
- Removing a parameter
- Renaming a parameter
- Changing a parameter from optional to mandatory
- Changing a parameter's type in an incompatible way

The following are **non-breaking** (allowed in minor/patch versions):

- Adding a new command
- Adding a new parameter (must be optional with a sensible default)
- Changing exact error message strings
- Adding new output properties (output types are coarse-grained)
- Internal implementation changes

### 3.2 Data Contracts (Public Artifacts)

#### Workflow Authoring Contract

- **Format**: PSD1 workflow definitions
- **Validation**: `Test-IdleWorkflow`
- **Stability**: The workflow schema is a stable contract
  - Unknown keys: **FAIL** (strict validation)
  - Required fields (Name, LifecycleEvent, Steps[].Name, Steps[].Type): **FAIL** if null/empty
  - `With` payload values: allow `null` and empty strings (supports "clear attribute" scenarios)

#### Lifecycle Request Contract

- **Format**: Object created by `New-IdleLifecycleRequest`
- **Required fields**: `LifecycleEvent`, `CorrelationId`
- **Optional fields**: `Actor`, `IdentityKeys`, `DesiredState`, `Changes`

#### Plan Export Contract

- **Format**: JSON from `Export-IdlePlan`
- **Stability**: The JSON schema is a stable contract for plan interchange
- **Use case**: Plan review, auditing, CI/CD integration

### 3.3 Explicit Non-Contracts

The following are **not** considered stable contracts and may change without notice:

- Exact error message strings (error types and parameters are stable)
- Undocumented internal object properties
- Internal module cmdlets (when accessed by path import)
- Internal helper functions

---

## 4. Canonical Formats

### 4.1 Workflow Authoring Format

**Canonical format**: PSD1 workflow definitions

Validated by `Test-IdleWorkflow`.

### 4.2 Plan Interchange Format

**Canonical format**: JSON from `Export-IdlePlan`

Used for:
- Plan review and auditing
- CI/CD integration
- External tooling

### 4.3 Non-Goals (v1.0)

JSON as a **workflow authoring format** is not a v1.0 goal.

---

## 5. Validation Strictness

### 5.1 Unknown Keys

Workflow definitions with **unknown keys** will **FAIL** validation.

This enforces a strict authoring contract and prevents typos/configuration drift.

### 5.2 Required vs. Optional Fields

- **Required contract fields** (e.g., step `Name`, step `Type`, request `LifecycleEvent`): **FAIL** if null/empty
- **`With` payload values**:
  - Required keys must exist
  - Values may be `null` or empty string (supports "clear attribute" scenarios)
  - Step contracts must document per-key null/empty allowance

---

## 6. Capability ID Baseline (v1.0)

### 6.1 Capability Namespace Convention

All capability IDs use the **IdLE.** namespace:

- ✅ `IdLE.Identity.Read`
- ✅ `IdLE.Mailbox.Info.Read`
- ❌ `Identity.Read` (un-namespaced, legacy)

New work **MUST** use the `IdLE.` namespace.

### 6.2 v1.0 Capability Baseline

The following capability IDs are frozen as the v1.0 baseline:

| Capability ID                         | Description |
|---------------------------------------|-------------|
| `IdLE.DirectorySync.Status`           | Read directory sync status |
| `IdLE.DirectorySync.Trigger`          | Trigger directory sync |
| `IdLE.Entitlement.Grant`              | Grant group membership/entitlement |
| `IdLE.Entitlement.List`               | List user entitlements |
| `IdLE.Entitlement.Revoke`             | Revoke group membership/entitlement |
| `IdLE.Identity.Attribute.Ensure`      | Ensure identity attribute value |
| `IdLE.Identity.Create`                | Create identity |
| `IdLE.Identity.Delete`                | Delete identity |
| `IdLE.Identity.Disable`               | Disable identity |
| `IdLE.Identity.Enable`                | Enable identity |
| `IdLE.Identity.Move`                  | Move identity (OU/container) |
| `IdLE.Mailbox.Info.Read`              | Read mailbox metadata/configuration (renamed from `IdLE.Mailbox.Read`) |
| `IdLE.Mailbox.OutOfOffice.Ensure`     | Ensure Out of Office configuration |
| `IdLE.Mailbox.Type.Ensure`            | Ensure mailbox type (User/Shared/etc.) |

### 6.3 Capability Rename (Pre-1.0)

**Deprecated (pre-1.0):** `IdLE.Mailbox.Read`  
**New:** `IdLE.Mailbox.Info.Read`

**Meaning**: "Read mailbox metadata/configuration required by IdLE steps" (does not read mailbox contents)

**Migration Policy**:
- The old capability ID is mapped to the new ID during planning
- A deprecation warning is emitted:
  ```
  WARNING: DEPRECATED: Capability 'IdLE.Mailbox.Read' is deprecated and will be removed in a future major version.
  Use 'IdLE.Mailbox.Info.Read' instead.
  ```
- The mapping will be removed in a future major version (post-1.0)

---

## 7. Deprecation Mechanism

### 7.1 Deprecation Warning Format

Deprecated supported cmdlets/parameters **MUST** emit a `Write-Warning` on use:

**Format**:
```
DEPRECATED: <Item> is deprecated in <version> and will be removed in <major_version>.
Use <replacement> instead.
```

**Example**:
```powershell
Write-Warning "DEPRECATED: Parameter 'OldName' is deprecated in v1.2 and will be removed in v2.0. Use 'NewName' instead."
```

### 7.2 Enforcement

Deprecation warnings are enforced by **Pester tests** that assert the warning exists.

### 7.3 Capability Deprecation

Deprecated capability IDs are automatically mapped to their replacements during planning, with a warning emitted.

See section 6.3 for the `IdLE.Mailbox.Read` → `IdLE.Mailbox.Info.Read` migration.

---

## 8. Step Capability Ownership

**Rule**: Step packs own required capabilities via step metadata catalogs.

**Implementation**:
- Step metadata is declared in `Get-IdleStepMetadataCatalog` functions
- Core engine enforces capability requirements during planning
- Workflows **do not** declare capabilities directly

**Example**:

```powershell
# src/IdLE.Steps.Mailbox/Public/Get-IdleStepMetadataCatalog.ps1
$catalog['IdLE.Step.Mailbox.GetInfo'] = @{
    RequiredCapabilities = @('IdLE.Mailbox.Info.Read')
}
```

---

## 9. Compatibility Guarantees

### 9.1 Semantic Versioning

IdLE follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (breaking): Incompatible API changes
- **MINOR** (feature): Backward-compatible functionality additions
- **PATCH** (fix): Backward-compatible bug fixes

### 9.2 What Constitutes a Breaking Change

See section 3.1 for details.

### 9.3 Deprecation Timeline

Deprecated features will be supported for **at least one minor version** before removal in the next major version.

**Example**:
- Deprecated in v1.2 → Removed in v2.0
- Deprecated in v1.8 → Removed in v2.0

---

## 10. Workflow and Request Schema Evolution

### 10.1 Adding Optional Fields

Adding new **optional** fields to workflow definitions or lifecycle requests is **non-breaking** (minor version).

### 10.2 Removing Fields

Removing fields is **breaking** (major version).

### 10.3 Renaming Fields

Renaming fields is **breaking** (major version).

Migration path: Support both old and new names with deprecation warnings for at least one minor version.

---

## 11. Testing and Verification

### 11.1 Stability Tests

Stability contract tests enforce the supported API surface:

```powershell
# Run stability tests
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -TestPath tests/StabilityContract.Tests.ps1
```

### 11.2 Deprecation Tests

Deprecation behavior is validated by Pester tests:

```powershell
# Run deprecation tests
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -TestPath tests/CapabilityDeprecation.Tests.ps1
```

---

## 12. References

- [AGENTS.md](../../AGENTS.md) - Agent operating manual
- [STYLEGUIDE.md](../../STYLEGUIDE.md) - Coding standards
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contributor workflow
- [architecture.md](./architecture.md) - Architecture decisions
- [security.md](./security.md) - Security and trust boundaries
- [provider-capabilities.md](./provider-capabilities.md) - Provider capability rules
- [providers-and-contracts.md](../reference/providers-and-contracts.md) - Provider contracts
