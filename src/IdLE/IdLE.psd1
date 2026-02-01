@{
    RootModule        = 'IdLE.psm1'
    ModuleVersion = '0.9.1'
    GUID              = 'e2f1c3a4-7b9d-4f2a-8c3e-1d5b6a7c8e9f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdentityLifecycleEngine (IdLE) meta-module. Imports IdLE.Core and optional packs.'
    PowerShellVersion = '7.0'

    # ScriptsToProcess runs before RequiredModules are imported
    # This script bootstraps PSModulePath for repo/zip layouts
    ScriptsToProcess = @('IdLE.Init.ps1')

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

    # NOTE: IdLE meta-module uses RootModule bootstrap instead of RequiredModules
    # to support both PSGallery/installed and repo/zip layouts without requiring
    # users to manually configure PSModulePath before first import.
    # The RootModule (IdLE.psm1) imports IdLE.Core and IdLE.Steps.Common with fallback logic.

    PrivateData = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Identity', 'Lifecycle', 'Automation', 'IdentityManagement', 'JML', 'Onboarding', 'Offboarding', 'AccountManagement')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
