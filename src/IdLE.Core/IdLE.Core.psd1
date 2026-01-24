@{
    RootModule        = 'IdLE.Core.psm1'
    ModuleVersion = '0.8.0'
    GUID              = 'c6232cd4-6fe9-4c37-a87b-eed8ce7e3517'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdLE Core engine: domain model, workflow loading/validation, plan builder and execution pipeline.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'New-IdleLifecycleRequestObject',
        'Test-IdleWorkflowDefinitionObject',
        'New-IdlePlanObject',
        'Invoke-IdlePlanObject',
        'Export-IdlePlanObject'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Identity', 'Lifecycle', 'Automation', 'IdentityManagement', 'JML', 'Onboarding', 'Offboarding', 'AccountManagement')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
