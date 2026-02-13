@{
    RootModule        = 'IdLE.Provider.DirectorySync.EntraConnect.psm1'
    ModuleVersion = '0.9.4'
    GUID              = 'a1b2c3d4-5e6f-7890-abcd-ef1234567890'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Entra Connect directory sync provider for IdLE (remote execution).'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    FunctionsToExport = @(
        'New-IdleEntraConnectDirectorySyncProvider'
    )

    PrivateData       = @{
        PSData = @{
            Tags         = @('IdentityLifecycleEngine', 'IdLE', 'Provider', 'DirectorySync', 'EntraConnect')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}
