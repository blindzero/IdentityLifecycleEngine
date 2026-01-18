@{
    RootModule        = 'IdLE.Provider.AD.psm1'
    ModuleVersion     = '0.8.0'
    GUID              = '8a7f3c2e-9b4d-4e1a-a8c6-5f9d2b1e3a4c'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Active Directory (on-prem) provider implementation for IdLE (Windows-only, requires RSAT/ActiveDirectory module).'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'New-IdleADIdentityProvider'
    )

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Provider', 'ActiveDirectory', 'AD')
            LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri   = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
