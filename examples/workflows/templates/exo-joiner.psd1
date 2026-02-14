@{
    Name           = 'ExchangeOnline Joiner - Mailbox Baseline'
    LifecycleEvent = 'Joiner'
    Description    = 'Verifies mailbox existence/type and applies a minimal safe baseline (idempotent).'

    Steps          = @(
        @{
            Name = 'GetMailboxInfo'
            Type = 'IdLE.Step.Mailbox.GetInfo'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
            }
        }
        @{
            Name = 'EnsureUserMailboxType'
            Type = 'IdLE.Step.Mailbox.EnsureType'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                MailboxType = 'User'
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mailbox baseline verified/applied for {{Request.Input.UserPrincipalName}}.'
            }
        }
    )
}
