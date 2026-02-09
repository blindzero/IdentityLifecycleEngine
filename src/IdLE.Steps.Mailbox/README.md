# IdLE.Steps.Mailbox

Provider-agnostic mailbox step pack for IdLE.

## Quick Start

```powershell
# Step example: Convert to shared mailbox
@{
    Name = 'ConvertToSharedMailbox'
    Type = 'IdLE.Step.Mailbox.EnsureType'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
        MailboxType = 'Shared'
    }
}
```

## Step Types

- **IdLE.Step.Mailbox.GetInfo** - Read mailbox details
- **IdLE.Step.Mailbox.EnsureType** - Convert mailbox type (User/Shared/Room/Equipment)
- **IdLE.Step.Mailbox.EnsureOutOfOffice** - Configure Out of Office settings

## Documentation

See the main IdLE documentation for:
- Detailed step usage and parameters
- Provider contract requirements
- Configuration examples
- Best practices
