@{
    RootModule        = 'IdLE.Steps.Mailbox.psm1'
    ModuleVersion     = '0.9.0'
    GUID              = 'f7e6d5c4-b3a2-9180-7e6f-5d4c3b2a1908'
    Author            = 'IdLE Contributors'
    CompanyName       = 'IdLE Project'
    Copyright         = '(c) 2025 IdLE Contributors. Licensed under Apache License 2.0.'
    Description       = 'Provider-agnostic mailbox step pack for IdentityLifecycleEngine'
    PowerShellVersion = '7.0'

    RequiredModules   = @('..\IdLE.Steps.Common\IdLE.Steps.Common.psd1')

    FunctionsToExport = @(
        'Get-IdleStepMetadataCatalog'
        'Invoke-IdleStepMailboxReport'
        'Invoke-IdleStepMailboxTypeEnsure'
        'Invoke-IdleStepMailboxOutOfOfficeEnsure'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Steps', 'Mailbox', 'ExchangeOnline')
            LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri   = 'https://github.com/blindzero/IdentityLifecycleEngine'
            IconUri      = ''
            ReleaseNotes = 'Provider-agnostic mailbox step pack for IdLE'
        }
    }
}
