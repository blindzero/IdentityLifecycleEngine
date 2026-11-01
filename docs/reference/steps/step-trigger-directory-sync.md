# IdLE.Step.TriggerDirectorySync

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.TriggerDirectorySync`
- **Module**: `IdLE.Steps.DirectorySync`
- **Implementation**: `Invoke-IdleStepTriggerDirectorySync`
- **Idempotent**: `Unknown`
- **Required Capabilities**: `IdLE.DirectorySync.Trigger`, `IdLE.DirectorySync.Status`

## Synopsis

Triggers a directory sync cycle and optionally waits for completion.

## Description

The engine passes the provider resolved from With.Provider
(default 'DirectorySync') as -Provider. The provider implements:

- StartSyncCycle(PolicyType, ComputerName, AuthSession)

- GetSyncCycleState(ComputerName, AuthSession)

The step is designed for remote execution and requires an elevated auth session
provided by the host's AuthSessionBroker.

Authentication is handled by the engine: With.AuthSessionName (optional) and With.AuthSessionOptions
select the session; without AuthSessionName the broker is asked for a default session.
ComputerName and PolicyType are provider-specific inputs and are validated by the selected provider.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `ComputerName` | String | No |  |  |
| `PolicyType` | String | No |  |  |
| `PollIntervalSeconds` | Int | No | `10` |  |
| `TimeoutSeconds` | Int | No | `600` |  |
| `Wait` | Bool | No | `$false` |  |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `DirectorySync` | Provider alias in `Providers`. |

## Example

```powershell
$step = @{
    Name = 'Trigger directory sync'
    Type = 'IdLE.Step.TriggerDirectorySync'
    With = @{
        AuthSessionName = 'DirectorySync'
        ComputerName = 'ad-sync1.corp.local'
        PolicyType = 'Delta'
        Wait = $true
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations
