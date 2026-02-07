@{
    RootModule        = 'IdLE.psm1'
    ModuleVersion = '0.9.2'
    GUID              = 'e2f1c3a4-7b9d-4f2a-8c3e-1d5b6a7c8e9f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdentityLifecycleEngine (IdLE) meta-module. Imports IdLE.Core and optional packs.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    # ScriptsToProcess runs before NestedModules are loaded
    # This script bootstraps PSModulePath for repo/zip layouts
    ScriptsToProcess = @('IdLE.Init.ps1')

    # NestedModules: Core and Steps.Common are loaded as nested dependencies
    # 
    # Source manifest strategy (repo/zip):
    #   - Uses NestedModules with relative paths (enables Import-Module ./src/IdLE/IdLE.psd1)
    #   - ScriptsToProcess adds src/ to PSModulePath for subsequent name-based imports
    # 
    # Published manifest strategy (PSGallery):
    #   - Packaging tool converts to: RequiredModules = @('IdLE.Core', 'IdLE.Steps.Common')
    #   - Removes NestedModules and ScriptsToProcess (standard PowerShell dependency resolution)
    NestedModules = @(
        '..\IdLE.Core\IdLE.Core.psd1',
        '..\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
    )

    FunctionsToExport = @(
        'Test-IdleWorkflow',
        'New-IdleLifecycleRequest',
        'New-IdlePlan',
        'Invoke-IdlePlan',
        'Export-IdlePlan',
        'New-IdleAuthSession'
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
