@{
    RootModule        = 'IdLE.Steps.Mailbox.psm1'
    ModuleVersion = '0.9.3'
    GUID              = 'f7e6d5c4-b3a2-9180-7e6f-5d4c3b2a1908'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Provider-agnostic mailbox step pack for IdLE.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    RequiredModules   = @('IdLE.Core', 'IdLE.Steps.Common')

    FunctionsToExport = @(
        'Get-IdleStepMetadataCatalog',
        'Invoke-IdleStepMailboxGetInfo',
        'Invoke-IdleStepMailboxTypeEnsure',
        'Invoke-IdleStepMailboxOutOfOfficeEnsure'
    )

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Steps', 'Mailbox')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}
