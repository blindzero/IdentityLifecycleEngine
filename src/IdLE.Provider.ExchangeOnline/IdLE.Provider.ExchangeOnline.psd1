@{
    RootModule        = 'IdLE.Provider.ExchangeOnline.psm1'
    ModuleVersion     = '0.9.0'
    GUID              = 'e8f9a3b1-4c2d-4a5b-9f7e-3d2c1a9b8e7f'
    Author            = 'IdLE Contributors'
    CompanyName       = 'IdLE Project'
    Copyright         = '(c) 2025 IdLE Contributors. Licensed under Apache License 2.0.'
    Description       = 'Exchange Online mailbox provider for IdentityLifecycleEngine'
    PowerShellVersion = '7.0'

    FunctionsToExport = @('New-IdleExchangeOnlineProvider')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Provider', 'ExchangeOnline', 'Mailbox')
            LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri   = 'https://github.com/blindzero/IdentityLifecycleEngine'
            IconUri      = ''
            ReleaseNotes = 'Exchange Online provider for mailbox lifecycle management'
        }
    }
}
