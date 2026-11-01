# StepMetadataCatalog.psd1 - IdLE.Steps.DirectorySync
#
# Data-only metadata catalog for directory sync step types.
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
    # IdLE.Step.TriggerDirectorySync - triggers a directory sync cycle and optionally waits for completion
    # Note: Even when With.Wait = $false, Status capability is advertised to keep planning deterministic.
    'IdLE.Step.TriggerDirectorySync' = @{
        Handler              = 'Invoke-IdleStepTriggerDirectorySync'
        RequiredCapabilities = @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
        Provider             = @{ DefaultAlias = 'DirectorySync' }
        WithSchema           = @{
            Keys = @{
                # ComputerName and PolicyType are provider-specific and validated by the provider.
                ComputerName        = @{ Type = 'String' }
                PolicyType          = @{ Type = 'String' }
                Wait                = @{ Type = 'Bool'; Default = $false }
                TimeoutSeconds      = @{ Type = 'Int'; Default = 600 }
                PollIntervalSeconds = @{ Type = 'Int'; Default = 10 }
            }
        }
    }
}
