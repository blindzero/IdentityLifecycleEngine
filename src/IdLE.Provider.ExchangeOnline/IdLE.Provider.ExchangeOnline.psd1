@{
    RootModule        = 'IdLE.Provider.ExchangeOnline.psm1'
    ModuleVersion = '0.9.1'
    GUID              = 'e8f9a3b1-4c2d-4a5b-9f7e-3d2c1a9b8e7f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Exchange Online mailbox provider implementation for IdLE (requires ExchangeOnlineManagement module).'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'New-IdleExchangeOnlineProvider'
    )

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Provider', 'ExchangeOnline', 'Mailbox')
            LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri   = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
