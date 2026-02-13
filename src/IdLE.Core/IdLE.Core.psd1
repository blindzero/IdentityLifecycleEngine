@{
    RootModule        = 'IdLE.Core.psm1'
    ModuleVersion = '0.9.4'
    GUID              = 'c6232cd4-6fe9-4c37-a87b-eed8ce7e3517'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'IdLE Core engine: domain model, workflow loading/validation, plan builder and execution pipeline.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    FunctionsToExport = @(
        'Assert-IdleNoScriptBlock',
        'Export-IdlePlanObject',
        'Invoke-IdlePlanObject',
        'Invoke-IdleProviderMethod',
        'New-IdleAuthSessionBroker',
        'New-IdleRequestObject',
        'New-IdlePlanObject',
        'Test-IdleProviderMethodParameter',
        'Test-IdleWorkflowDefinitionObject'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Core', 'Engine', 'Workflow', 'Plan', 'Execution', 'Validation')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}

