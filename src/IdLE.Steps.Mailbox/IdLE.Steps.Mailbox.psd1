@{
    RootModule        = 'IdLE.Steps.Mailbox.psm1'
    ModuleVersion = '0.9.1'
    GUID              = 'f7e6d5c4-b3a2-9180-7e6f-5d4c3b2a1908'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Provider-agnostic mailbox step pack for IdLE.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '0.9.1' },
        @{ ModuleName = 'IdLE.Steps.Common'; ModuleVersion = '0.9.1' }
    )

    FunctionsToExport = @(
        'Get-IdleStepMetadataCatalog',
        'Invoke-IdleStepMailboxGetInfo',
        'Invoke-IdleStepMailboxTypeEnsure',
        'Invoke-IdleStepMailboxOutOfOfficeEnsure'
    )

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Steps', 'Mailbox')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
