@{
    RootModule        = 'IdLE.psm1'
    ModuleVersion = '0.9.1'
    GUID              = 'e2f1c3a4-7b9d-4f2a-8c3e-1d5b6a7c8e9f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdentityLifecycleEngine (IdLE) meta-module. Imports IdLE.Core and optional packs.'
    PowerShellVersion = '7.0'

    # ScriptsToProcess runs BEFORE NestedModules are loaded
    # This allows us to set environment variables to suppress internal module warnings
    ScriptsToProcess = @('IdLE.Init.ps1')

    RequiredModules = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '0.9.1' },
        @{ ModuleName = 'IdLE.Steps.Common'; ModuleVersion = '0.9.1' }
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

    # NOTE: IdLE depends on IdLE.Core and IdLE.Steps.Common.
    # These are declared as RequiredModules so they are properly resolved from PSModulePath
    # when installed from PowerShell Gallery.

    PrivateData = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Identity', 'Lifecycle', 'Automation', 'IdentityManagement', 'JML', 'Onboarding', 'Offboarding', 'AccountManagement')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
