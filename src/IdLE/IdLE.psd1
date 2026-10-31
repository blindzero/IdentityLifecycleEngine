@{
    RootModule        = 'IdLE.psm1'
    ModuleVersion = '0.9.8'
    GUID              = 'e2f1c3a4-7b9d-4f2a-8c3e-1d5b6a7c8e9f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdentityLifecycleEngine (IdLE). Bundles the engine, all first-party step packs and providers.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    # ScriptsToProcess runs before NestedModules are loaded.
    # It bootstraps PSModulePath for repo/zip layouts and rejects sessions that already
    # contain standalone IdLE.* modules (mixed versions).
    ScriptsToProcess = @('IdLE.Init.ps1')

    # NestedModules: all first-party modules shipped in the IdLE bundle.
    # This list is the single source of truth for the bundle content.
    #
    # Source manifest (repo/zip): relative paths to the sibling module folders under src/.
    # Published manifest (PSGallery): the packaging tool (tools/New-IdleModulePackage.ps1)
    # copies the modules to 'Modules/<Name>/' and rewrites these entries accordingly.
    NestedModules = @(
        '..\IdLE.Core\IdLE.Core.psd1',
        '..\IdLE.Steps.Common\IdLE.Steps.Common.psd1',
        '..\IdLE.Steps.DirectorySync\IdLE.Steps.DirectorySync.psd1',
        '..\IdLE.Steps.Mailbox\IdLE.Steps.Mailbox.psd1',
        '..\IdLE.Provider.AD\IdLE.Provider.AD.psd1',
        '..\IdLE.Provider.EntraID\IdLE.Provider.EntraID.psd1',
        '..\IdLE.Provider.ExchangeOnline\IdLE.Provider.ExchangeOnline.psd1',
        '..\IdLE.Provider.DirectorySync.EntraConnect\IdLE.Provider.DirectorySync.EntraConnect.psd1',
        '..\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'
    )

    FunctionsToExport = @(
        'Test-IdleWorkflow',
        'New-IdleRequest',
        'New-IdlePlan',
        'Invoke-IdlePlan',
        'Export-IdlePlan',
        'New-IdleAuthSession',
        'New-IdleADIdentityProvider',
        'New-IdleEntraIDIdentityProvider',
        'New-IdleExchangeOnlineProvider',
        'New-IdleEntraConnectDirectorySyncProvider',
        'New-IdleMockIdentityProvider'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Identity', 'Lifecycle', 'Automation', 'IdentityManagement', 'JML', 'Onboarding', 'Offboarding', 'AccountManagement')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}

