# IdLE.Steps.Mailbox

Provider-agnostic mailbox step pack for IdLE.

## Quick Start

```powershell
# Step example: Convert to shared mailbox
@{
    Name = 'ConvertToSharedMailbox'
    Type = 'IdLE.Step.Mailbox.Type.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
        MailboxType = 'Shared'
    }
}
```

## Step Types

- **IdLE.Step.Mailbox.GetInfo** - Read mailbox details
- **IdLE.Step.Mailbox.Type.Ensure** - Convert mailbox type (User/Shared/Room/Equipment)
- **IdLE.Step.Mailbox.OutOfOffice.Ensure** - Configure Out of Office settings

## Documentation

See the main IdLE documentation for:
- Detailed step usage and parameters
- Provider contract requirements
- Configuration examples
- Best practices
