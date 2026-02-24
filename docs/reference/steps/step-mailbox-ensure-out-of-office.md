# IdLE.Step.Mailbox.EnsureOutOfOffice

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsureOutOfOffice`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxOutOfOfficeEnsure`
- **Idempotent**: `Yes`

## Synopsis

Ensures that a mailbox Out of Office (OOF) configuration matches the desired state.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement an EnsureOutOfOffice
method with the signature (IdentityKey, Config, AuthSession) and return an object
that contains a boolean property 'Changed'.

The step is idempotent by design: it converges OOF configuration to the desired state.

Out of Office Config shape (data-only hashtable):

- Mode: 'Disabled' | 'Enabled' | 'Scheduled' (required)

- Start: DateTime (required when Mode = 'Scheduled')

- End: DateTime (required when Mode = 'Scheduled')

- InternalMessage: string (optional)

- ExternalMessage: string (optional)

- ExternalAudience: 'None' | 'Known' | 'All' (optional, default provider-specific)

- MessageFormat: 'Text' | 'Html' (optional, default 'Text')
  When set to 'Html', messages are treated as HTML markup and passed through without modification.
  When set to 'Text', messages are treated as plain text.
  Providers may normalize HTML to ensure stable idempotency (e.g., handling server-side wrapping).

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method.

- If With.AuthSessionName is absent, defaults to With.Provider value (e.g., 'ExchangeOnline').

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Admin' \}).

## Inputs (With.*)

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `Config` | `hashtable` | Yes | — | Configuration hashtable for the operation. See the Description section for the full property schema. |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1 — In workflow definition (enable OOF)

```powershell
# In workflow definition (enable OOF):
@{
    Name = 'Enable Out of Office'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider        = 'ExchangeOnline'
        IdentityKey     = 'user@contoso.com'
        Config          = @{
            Mode            = 'Enabled'
            InternalMessage = 'I am out of office.'
            ExternalMessage = 'I am currently unavailable.'
            ExternalAudience = 'All'
            MessageFormat   = 'Text'
        }
    }
}
```

### Example 2 — In workflow definition (with ValueFrom for dynamic values)

```powershell
# In workflow definition (with ValueFrom for dynamic values):
@{
    Name = 'Enable Out of Office for Leaver'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider        = 'ExchangeOnline'
        IdentityKey     = @{ ValueFrom = 'Request.Intent.UserPrincipalName' }
        Config          = @{
            Mode            = 'Enabled'
            InternalMessage = 'This person is no longer with the organization. For assistance, please contact their manager or the main office.'
            ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
            ExternalAudience = 'All'
        }
    }
}
```

### Example 3 — In workflow definition (scheduled OOF)

```powershell
# In workflow definition (scheduled OOF):
@{
    Name = 'Schedule Out of Office'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider        = 'ExchangeOnline'
        IdentityKey     = 'user@contoso.com'
        Config          = @{
            Mode            = 'Scheduled'
            Start           = '2025-02-01T00:00:00Z'
            End             = '2025-02-15T00:00:00Z'
            InternalMessage = 'I am on vacation until February 15.'
            ExternalMessage = 'I am currently out of office.'
        }
    }
}
```

### Example 4 — In workflow definition (disable OOF)

```powershell
# In workflow definition (disable OOF):
@{
    Name = 'Disable Out of Office'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
            Mode = 'Disabled'
        }
    }
}
```

### Example 5 — In workflow definition (HTML formatted message)

```powershell
# In workflow definition (HTML formatted message):
@{
    Name = 'Enable Out of Office with HTML'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
            Mode            = 'Enabled'
            MessageFormat   = 'Html'
            InternalMessage = '<p>I am out of office.</p><p>For urgent matters, contact <a href="mailto:manager@contoso.com">my manager</a>.</p>'
            ExternalMessage = '<p>I am currently unavailable.</p><p>Please contact our <strong>Service Desk</strong> at servicedesk@contoso.com.</p>'
            ExternalAudience = 'All'
        }
    }
}
```

### Example 6 — Template usage with dynamic manager attributes (Leaver scenario)

```powershell
# Template usage with dynamic manager attributes (Leaver scenario):
# Note: Templates are resolved during planning against the request object.
# Host must enrich request.Intent with manager data before calling New-IdlePlan.

# Host-side enrichment (example):
# $user = Get-ADUser -Identity 'max.power' -Properties Manager
# $mgr = if ($user.Manager) {
#     Get-ADUser -Identity $user.Manager -Properties DisplayName, Mail
# } else {
#     # Fallback manager/contact to avoid null template values
#     [pscustomobject]@{
#         DisplayName = 'Service Desk'
#         Mail        = 'servicedesk@contoso.com'
#     }
# }
# $req = New-IdleRequest -LifecycleEvent 'Leaver' -Actor $env:USERNAME -Intent @{
#   Manager = @{ DisplayName = $mgr.DisplayName; Mail = $mgr.Mail }
# }

# Workflow step with template variables:
@{
    Name = 'Set OOF with Manager Contact'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider        = 'ExchangeOnline'
        IdentityKey     = 'max.power@contoso.com'
        Config          = @{
            Mode            = 'Enabled'
            InternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.Intent.Manager.DisplayName}} ({{Request.Intent.Manager.Mail}}).'
            ExternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.Intent.Manager.Mail}}.'
            ExternalAudience = 'All'
        }
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations
