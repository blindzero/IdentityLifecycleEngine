# StepMetadataCatalog.psd1 - IdLE.Steps.DirectorySync
#
# Data-only metadata catalog for directory sync step types.
# This file is loaded by the engine (manifest PrivateData.IdLE.StepCatalog) and by Get-IdleStepMetadataCatalog.
# It must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   Handler              - handler function exported by this module (bound to this module by the engine)
#   RequiredCapabilities - capability identifiers the step requires from providers
#   WithSchema           - declares the With key contract for plan-time validation:
#     RequiredKeys         - keys that MUST be present in With
#     OptionalKeys         - keys that MAY be present in With
#
@{
    # IdLE.Step.TriggerDirectorySync - triggers a directory sync cycle and optionally waits for completion
    # Note: Even when With.Wait = $false, Status capability is advertised to keep planning deterministic.
    'IdLE.Step.TriggerDirectorySync' = @{
        Handler              = 'Invoke-IdleStepTriggerDirectorySync'
        RequiredCapabilities = @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
        WithSchema           = @{
            RequiredKeys = @()
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions', 'ComputerName', 'PolicyType', 'Wait', 'TimeoutSeconds', 'PollIntervalSeconds')
        }
    }
}
