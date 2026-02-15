@{
    Name           = 'Complete Joiner - ExchangeOnline Mailbox Provisioning'
    LifecycleEvent = 'Joiner'
    Description    = 'Joiner workflow for Exchange Online: ensures mailbox type is User and Out of Office is disabled.'

    Steps = @(
        @{
            Name        = 'GetMailboxInfo'
            Type        = 'IdLE.Step.Mailbox.GetInfo'
            Description = 'Reads mailbox details (useful for auditing and troubleshooting).'
            With        = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
            }
        }

        @{
            Name        = 'EnsureUserMailboxType'
            Type        = 'IdLE.Step.Mailbox.EnsureType'
            Description = 'Ensures the mailbox is a regular user mailbox.'
            With        = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                # Allowed values: User | Shared | Room | Equipment
                MailboxType = 'User'
            }
        }

        @{
            Name        = 'DisableOutOfOffice'
            Type        = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            Description = 'Ensures Out of Office is disabled for a new joiner mailbox.'
            With        = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                Config      = @{
                    # Allowed values: Disabled | Enabled | Scheduled
                    Mode = 'Disabled'
                }
            }
        }

        @{
            Name        = 'EmitCompletionEvent'
            Type        = 'IdLE.Step.EmitEvent'
            Description = 'Completion marker.'
            With        = @{
                Message = 'EXO joiner completed: mailbox type ensured (User) and Out of Office disabled.'
            }
        }
    )
}
