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

- StartSyncCycle(PolicyType, ComputerName, AuthSession)

- GetSyncCycleState(ComputerName, AuthSession)

The step is designed for remote execution and requires an elevated auth session
provided by the host's AuthSessionBroker.

Authentication:

- With.AuthSessionName (optional): routing key for AuthSessionBroker

- With.AuthSessionOptions (optional, hashtable): forwarded to broker for session selection

- If AuthSessionName is omitted, the broker is asked for a default session

- ScriptBlocks in AuthSessionOptions are rejected (security boundary)

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `ComputerName` | Yes | See step description for details |
| `PolicyType` | Yes | Type of policy (e.g., Delta, Initial) |

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

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations
