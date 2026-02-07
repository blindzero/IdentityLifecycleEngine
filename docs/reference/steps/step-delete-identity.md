# DeleteIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `DeleteIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepDeleteIdentity`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Identity.Delete`

## Synopsis

Deletes an identity from the target system.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements DeleteIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already deleted, the provider
should return Changed = $false.

IMPORTANT: This step requires the provider to advertise the IdLE.Identity.Delete
capability, which is typically opt-in for safety. The provider must be configured
to allow deletion (e.g., AllowDelete = $true for AD provider).

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

This step may not require specific input keys, or they could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'DeleteIdentity Example'
  Type = 'IdLE.Step.DeleteIdentity'
  With = @{
    # See step description for available options
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations
