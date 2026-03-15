# StepMetadataCatalog.psd1 - IdLE.Steps.Mailbox
#
# Data-only metadata catalog for mailbox step types.
# This file is loaded by Get-IdleStepMetadataCatalog and must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   RequiredCapabilities - capability identifiers the step requires from providers
#   WithSchema           - declares the With key contract for plan-time validation:
#     RequiredKeys         - keys that MUST be present in With
#     OptionalKeys         - keys that MAY be present in With
#
@{
    # IdLE.Step.Mailbox.GetInfo - reads mailbox details for an identity
    'IdLE.Step.Mailbox.GetInfo'          = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.Mailbox.EnsureType - idempotently converts a mailbox to the specified type
    # MailboxType accepts: User, Shared, Room, Equipment
    'IdLE.Step.Mailbox.EnsureType'       = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.Type.Ensure')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'MailboxType')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.Mailbox.EnsureOutOfOffice - idempotently configures out-of-office settings
    # Config accepts: Mode (required), Start/End (required when Mode=Scheduled),
    #   InternalMessage, ExternalMessage, ExternalAudience, MessageFormat (optional)
    'IdLE.Step.Mailbox.EnsureOutOfOffice' = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.OutOfOffice.Ensure')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Config')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.Mailbox.EnsurePermissions - idempotently manages delegate permissions
    # Permissions is an array of hashtables with: AssignedUser, Right, Ensure
    'IdLE.Step.Mailbox.EnsurePermissions' = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.Permissions.Ensure')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Permissions')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }
}
