@{
    RootModule        = 'IdLE.psm1'
    ModuleVersion = '0.3.0'
    GUID              = 'e2f1c3a4-7b9d-4f2a-8c3e-1d5b6a7c8e9f'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdentityLifecycleEngine (IdLE) meta-module. Imports IdLE.Core and optional packs.'
    PowerShellVersion = '7.0'

    NestedModules = @('..\IdLE.Core\IdLE.Core.psd1')

    FunctionsToExport = @(
        'Test-IdleWorkflow',
        'New-IdleLifecycleRequest',
        'New-IdlePlan',
        'Invoke-IdlePlan',
        'Export-IdlePlan'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()

    # NOTE: IdLE depends on IdLE.Core.
    # We intentionally do not use 'RequiredModules' to keep repo-clone imports working
    # when modules are imported via relative paths (IdLE.Core may not be on PSModulePath).

    PrivateData = @{
        PSData = @{
            Tags       = @('Identity Lifecycle Engine', 'IdLE', 'Identity', 'Lifecycle', 'Automation', 'Identity Management', 'JML', 'Onboarding', 'Offboarding', 'Account Management')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
