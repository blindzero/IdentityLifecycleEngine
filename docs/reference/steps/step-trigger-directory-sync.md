# IdLE.Step.TriggerDirectorySync

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.TriggerDirectorySync`
- **Module**: `IdLE.Steps.DirectorySync`
- **Implementation**: `Invoke-IdleStepTriggerDirectorySync`
- **Idempotent**: `Unknown`

## Synopsis

Triggers a directory sync cycle and optionally waits for completion.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements:

- StartSyncCycle(PolicyType, AuthSession)

- GetSyncCycleState(AuthSession)

The step is designed for remote execution and requires an elevated auth session
provided by the host's AuthSessionBroker.

Authentication:

- With.AuthSessionName (required): routing key for AuthSessionBroker

- With.AuthSessionOptions (optional, hashtable): forwarded to broker for session selection

- ScriptBlocks in AuthSessionOptions are rejected (security boundary)

## Inputs (With.*)

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `AuthSessionName` | `string` | Yes | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `PolicyType` | `string` | Yes | ``Delta`` | Sync policy type: ``Delta`` \| ``Initial``. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1

```powershell
$step = @{
    Name = 'Trigger directory sync'
    Type = 'IdLE.Step.TriggerDirectorySync'
    With = @{
        AuthSessionName = 'DirectorySync'
        PolicyType = 'Delta'
        Wait = $true
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations
