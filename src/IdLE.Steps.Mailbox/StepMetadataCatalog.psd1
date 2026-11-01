# StepMetadataCatalog.psd1 - IdLE.Steps.Mailbox
#
# Data-only metadata catalog for mailbox step types.
# This file is loaded by the engine (manifest PrivateData.IdLE.StepCatalog) and by Get-IdleStepMetadataCatalog.
# It must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   Handler              - handler function exported by this module (bound to this module by the engine)
#   RequiredCapabilities - capability identifiers the step requires from providers
#   Provider             - (optional) the step uses one provider: @{ DefaultAlias = '<alias>' }.
#                          The engine resolves it and adds the With keys Provider, AuthSessionName, AuthSessionOptions.
#   WithSchema           - typed With contract validated at plan time (see docs/extend/steps.md):
#     Keys                 - key name -> @{ Type; Required; Default; AllowedValues; AllowEmpty; Keys; Items; ... }
#
@{
    # Mailbox steps name their auth session after the provider alias (e.g. 'ExchangeOnline')
    # unless With.AuthSessionName is set (Provider.AuthSessionNameFromAlias).

    # IdLE.Step.Mailbox.GetInfo - reads mailbox details for an identity
    'IdLE.Step.Mailbox.GetInfo'           = @{
        Handler              = 'Invoke-IdleStepMailboxGetInfo'
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read')
        Provider             = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.Mailbox.EnsureType - idempotently converts a mailbox to the specified type
    'IdLE.Step.Mailbox.EnsureType'        = @{
        Handler              = 'Invoke-IdleStepMailboxTypeEnsure'
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.Type.Ensure')
        Provider             = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                MailboxType = @{ Type = 'String'; Required = $true; AllowedValues = @('User', 'Shared', 'Room', 'Equipment') }
            }
        }
    }

    # IdLE.Step.Mailbox.EnsureOutOfOffice - idempotently configures out-of-office settings
    # Start/End are required when Mode = 'Scheduled' (checked by the step); DateTime or string.
    'IdLE.Step.Mailbox.EnsureOutOfOffice' = @{
        Handler              = 'Invoke-IdleStepMailboxOutOfOfficeEnsure'
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.OutOfOffice.Ensure')
        Provider             = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Config      = @{
                    Type     = 'Hashtable'
                    Required = $true
                    Keys     = @{
                        Mode             = @{ Type = 'String'; Required = $true; AllowedValues = @('Disabled', 'Enabled', 'Scheduled') }
                        Start            = @{ Type = 'Any' }
                        End              = @{ Type = 'Any' }
                        InternalMessage  = @{ Type = 'String'; AllowEmpty = $true }
                        ExternalMessage  = @{ Type = 'String'; AllowEmpty = $true }
                        ExternalAudience = @{ Type = 'String'; AllowedValues = @('None', 'Known', 'All') }
                        MessageFormat    = @{ Type = 'String'; AllowedValues = @('Text', 'Html') }
                    }
                }
            }
        }
    }

    # IdLE.Step.Mailbox.EnsurePermissions - idempotently manages delegate permissions
    'IdLE.Step.Mailbox.EnsurePermissions' = @{
        Handler              = 'Invoke-IdleStepMailboxPermissionsEnsure'
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.Permissions.Ensure')
        Provider             = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Permissions = @{
                    Type     = 'Array'
                    Required = $true
                    Items    = @{
                        Type = 'Hashtable'
                        Keys = @{
                            AssignedUser = @{ Type = 'String'; Required = $true }
                            Right        = @{ Type = 'String'; Required = $true; AllowedValues = @('FullAccess', 'SendAs', 'SendOnBehalf') }
                            Ensure       = @{ Type = 'String'; Required = $true; AllowedValues = @('Present', 'Absent') }
                        }
                    }
                }
            }
        }
    }
}
