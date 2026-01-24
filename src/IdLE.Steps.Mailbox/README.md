# IdLE.Steps.Mailbox

Provider-agnostic mailbox step pack for **IdentityLifecycleEngine (IdLE)**.

## Overview

This step pack provides mailbox-focused lifecycle operations that work with any provider
implementing the **mailbox provider contract**.

The steps are **domain-oriented** (mailbox operations) rather than provider-branded,
ensuring maximum portability across Exchange Online, on-premises Exchange, and future providers.

## Step Types

### IdLE.Step.Mailbox.Report

Read mailbox details and return a structured snapshot.

```powershell
@{
    Name = 'Report user mailbox'
    Type = 'IdLE.Step.Mailbox.Report'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
    }
}
```

**Returns**: Mailbox object in `State.Mailbox` (read-only, Changed = false)

---

### IdLE.Step.Mailbox.Type.Ensure

Idempotent mailbox type conversion (User ↔ Shared, Room, Equipment).

```powershell
@{
    Name = 'Convert to shared mailbox'
    Type = 'IdLE.Step.Mailbox.Type.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        DesiredType = 'Shared'
    }
}
```

**Supported types**:
- `User` - Regular user mailbox
- `Shared` - Shared mailbox (team mailbox)
- `Room` - Room resource mailbox
- `Equipment` - Equipment resource mailbox

**Returns**: StepResult with `Changed` flag (true if conversion occurred)

---

### IdLE.Step.Mailbox.OutOfOffice.Ensure

Idempotent Out of Office (OOF) configuration.

```powershell
# Enable OOF
@{
    Name = 'Enable Out of Office'
    Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
            Mode            = 'Enabled'
            InternalMessage = 'I am out of office.'
            ExternalMessage = 'I am currently unavailable.'
            ExternalAudience = 'All'
        }
    }
}

# Scheduled OOF
@{
    Name = 'Schedule Out of Office'
    Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
            Mode  = 'Scheduled'
            Start = '2025-02-01T00:00:00Z'
            End   = '2025-02-15T00:00:00Z'
            InternalMessage = 'I am on vacation until February 15.'
        }
    }
}

# Disable OOF
@{
    Name = 'Disable Out of Office'
    Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{ Mode = 'Disabled' }
    }
}
```

**Config shape** (data-only hashtable):
- `Mode`: `'Disabled'` | `'Enabled'` | `'Scheduled'` (required)
- `Start`: DateTime (required when Mode = 'Scheduled')
- `End`: DateTime (required when Mode = 'Scheduled')
- `InternalMessage`: string (optional)
- `ExternalMessage`: string (optional)
- `ExternalAudience`: `'None'` | `'Known'` | `'All'` (optional)

**Returns**: StepResult with `Changed` flag (true if OOF settings were updated)

---

## Required Provider Capabilities

Each step declares required provider capabilities via metadata catalog:

| Step Type | Required Capabilities |
|-----------|----------------------|
| `IdLE.Step.Mailbox.Report` | `IdLE.Mailbox.Read` |
| `IdLE.Step.Mailbox.Type.Ensure` | `IdLE.Mailbox.Read`, `IdLE.Mailbox.Type.Ensure` |
| `IdLE.Step.Mailbox.OutOfOffice.Ensure` | `IdLE.Mailbox.Read`, `IdLE.Mailbox.OutOfOffice.Ensure` |

The IdLE planner automatically validates that the selected provider advertises these capabilities.

---

## Authentication Convention

**Option B (Convention)**: If `With.AuthSessionName` is not specified, the step defaults it to `With.Provider`.

Example:
```powershell
With = @{
    Provider    = 'ExchangeOnline'
    IdentityKey = 'user@contoso.com'
    # AuthSessionName defaults to 'ExchangeOnline' if omitted
}
```

Explicit override:
```powershell
With = @{
    Provider         = 'ExchangeOnline'
    IdentityKey      = 'user@contoso.com'
    AuthSessionName  = 'ExchangeOnline-Tier0'
    AuthSessionOptions = @{ Role = 'Tier0' }
}
```

---

## Provider Contract

Providers implementing the mailbox contract must expose:

- `GetMailbox(IdentityKey, AuthSession)` → returns mailbox object
- `EnsureMailboxType(IdentityKey, DesiredType, AuthSession)` → returns result with `Changed` flag
- `GetOutOfOffice(IdentityKey, AuthSession)` → returns OOF config object
- `EnsureOutOfOffice(IdentityKey, Config, AuthSession)` → returns result with `Changed` flag

Reference implementation: **IdLE.Provider.ExchangeOnline**

---

## See Also

- [IdLE.Provider.ExchangeOnline](../IdLE.Provider.ExchangeOnline/README.md) - Exchange Online provider
- [Capability Documentation](../../docs/advanced/provider-capabilities.md)
- [Step Reference](../../docs/reference/steps-and-metadata.md)

## License

Apache License 2.0 - see [LICENSE.md](../../LICENSE.md)
