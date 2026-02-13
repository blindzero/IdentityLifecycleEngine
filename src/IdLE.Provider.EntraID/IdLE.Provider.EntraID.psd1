@{
    RootModule        = 'IdLE.Provider.EntraID.psm1'
    ModuleVersion = '0.9.4'
    GUID              = 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Microsoft Entra ID (Azure AD) provider implementation for IdLE using Microsoft Graph API.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    FunctionsToExport = @(
        'New-IdleEntraIDIdentityProvider'
    )

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Provider', 'EntraID', 'AzureAD', 'MicrosoftGraph')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}
