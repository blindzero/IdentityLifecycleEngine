# IdLE.Step.Mailbox.EnsureOutOfOffice

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsureOutOfOffice`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxOutOfOfficeEnsure`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Mailbox.Info.Read`, `IdLE.Mailbox.OutOfOffice.Ensure`

## Synopsis

Ensures that a mailbox Out of Office (OOF) configuration matches the desired state.

## Description

The engine passes the provider resolved from With.Provider
(default 'ExchangeOnline') as -Provider. The provider implements an EnsureOutOfOffice
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

Authentication is handled by the engine: without With.AuthSessionName the session is named after the
provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `Config` | Hashtable | Yes |  | Keys: `End`, `ExternalAudience`, `ExternalMessage`, `InternalMessage`, `MessageFormat`, `Mode` (required), `Start` |
| `IdentityKey` | String | Yes |  |  |
| `AuthSessionName` | String | No | provider alias | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `ExchangeOnline` | Provider alias in `Providers`. |

## Example

### Example 1

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

### Example 2

```powershell
# In workflow definition (with a template for dynamic values):
@{
    Name = 'Enable Out of Office for Leaver'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @{
        Provider        = 'ExchangeOnline'
        IdentityKey     = '{{Request.Intent.UserPrincipalName}}'
        Config          = @{
            Mode            = 'Enabled'
            InternalMessage = 'This person is no longer with the organization. For assistance, please contact their manager or the main office.'
            ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
            ExternalAudience = 'All'
        }
    }
}
```

### Example 3

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

### Example 4

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

### Example 5

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

### Example 6

# Host-side enrichment (example):
# $user = Get-ADUser -Identity 'max.power' -Properties Manager
# $mgr = if ($user.Manager) \{
#     Get-ADUser -Identity $user.Manager -Properties DisplayName, Mail
# \} else \{
#     # Fallback manager/contact to avoid null template values
#     [pscustomobject]@\{
#         DisplayName = 'Service Desk'
#         Mail        = 'servicedesk@contoso.com'
#     \}
# \}
# $req = New-IdleRequest -LifecycleEvent 'Leaver' -Actor $env:USERNAME -Intent @\{
#   Manager = @\{ DisplayName = $mgr.DisplayName; Mail = $mgr.Mail \}
# \}

# Workflow step with template variables:
@\{
    Name = 'Set OOF with Manager Contact'
    Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
    With = @\{
        Provider        = 'ExchangeOnline'
        IdentityKey     = 'max.power@contoso.com'
        Config          = @\{
            Mode            = 'Enabled'
            InternalMessage = 'This mailbox is no longer monitored. Please contact \{\{Request.Intent.Manager.DisplayName\}\} (\{\{Request.Intent.Manager.Mail\}\}).'
            ExternalMessage = 'This mailbox is no longer monitored. Please contact \{\{Request.Intent.Manager.Mail\}\}.'
            ExternalAudience = 'All'
        \}
    \}
\}

```powershell
# Template usage with dynamic manager attributes (Leaver scenario):
# Note: Templates are resolved during planning against the request object.
# Host must enrich request.Intent with manager data before calling New-IdlePlan.
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations
