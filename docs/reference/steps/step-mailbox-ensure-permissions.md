# IdLE.Step.Mailbox.EnsurePermissions

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsurePermissions`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxPermissionsEnsure`
- **Idempotent**: `Yes`

## Synopsis

Ensures that mailbox delegate permissions match the desired state.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement an EnsureMailboxPermissions
method with the signature (IdentityKey, Permissions, AuthSession) and return an object
that contains a boolean property 'Changed'.

The step is idempotent by design: it converges mailbox delegate permissions to the desired
state by computing the delta between current and desired permissions and applying only the
necessary changes.

Supported rights (v1):

- FullAccess

- SendAs

- SendOnBehalf

Permissions array shape (data-only):
Each entry must be a hashtable with:

- AssignedUser: string (required) - UPN or SMTP address of the delegate

- Right: 'FullAccess' | 'SendAs' | 'SendOnBehalf' (required)

- Ensure: 'Present' | 'Absent' (required)

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method.

- If With.AuthSessionName is absent, defaults to With.Provider value (e.g., 'ExchangeOnline').

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Admin' \}).

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |
| `Permissions` | Yes | See step description for details |

## Example

### Example 1

```powershell
# In workflow definition (grant FullAccess and SendAs):
@{
    Name = 'Set Shared Mailbox Permissions'
    Type = 'IdLE.Step.Mailbox.EnsurePermissions'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'shared@contoso.com'
        Permissions = @(
            @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs';     Ensure = 'Present' }
        )
    }
}
```

### Example 2

```powershell
# In workflow definition (revoke access):
@{
    Name = 'Revoke Mailbox Access'
    Type = 'IdLE.Step.Mailbox.EnsurePermissions'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'shared@contoso.com'
        Permissions = @(
            @{ AssignedUser = 'leaver@contoso.com'; Right = 'FullAccess';   Ensure = 'Absent' }
            @{ AssignedUser = 'leaver@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Absent' }
        )
    }
}
```

### Example 3

```powershell
# With dynamic identity from request:
@{
    Name = 'Grant Team Mailbox Access'
    Type = 'IdLE.Step.Mailbox.EnsurePermissions'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'team@contoso.com'
        Permissions = @(
            @{ AssignedUser = @{ ValueFrom = 'Request.Intent.UserPrincipalName' }; Right = 'FullAccess'; Ensure = 'Present' }
        )
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations
