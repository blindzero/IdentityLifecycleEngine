@{
    RootModule        = 'IdLE.Provider.Mock.psm1'
    ModuleVersion = '0.3.0'
    GUID              = 'e661d3d6-1797-4cb1-b173-474982dbd653'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Mock provider implementation for IdLE (in-memory, deterministic).'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'New-IdleMockIdentityProvider'
    )

    PrivateData       = @{
        PSData = @{
            Tags         = @('Identity Lifecycle Engine', 'IdLE', 'Provider', 'Mock')
            LicenseUri   = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri   = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
