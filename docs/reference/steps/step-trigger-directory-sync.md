# TriggerDirectorySync

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `TriggerDirectorySync`
- **Module**: `IdLE.Steps.DirectorySync`
- **Implementation**: `Invoke-IdleStepTriggerDirectorySync`
- **Idempotent**: `Unknown`
- **Required Capabilities**: `IdLE.DirectorySync.Trigger`, `IdLE.DirectorySync.Status`

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

This step may not require specific input keys, or they could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'TriggerDirectorySync Example'
  Type = 'IdLE.Step.TriggerDirectorySync'
  With = @{
    # See step description for available options
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations
