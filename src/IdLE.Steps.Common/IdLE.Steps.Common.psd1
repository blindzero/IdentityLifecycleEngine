@{
    RootModule        = 'IdLE.Steps.Common.psm1'
    ModuleVersion = '0.9.3'
    GUID              = '9bdf5e97-0344-4191-82ed-c534bd7cb9b5'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Common built-in steps for IdLE.'
    PowerShellVersion = '7.0'
    HelpInfoUri       = 'https://blindzero.github.io/IdentityLifecycleEngine/'

    RequiredModules   = @('IdLE.Core')

    FunctionsToExport = @(
        'Get-IdleStepMetadataCatalog',
        'Invoke-IdleStepEmitEvent',
        'Invoke-IdleStepEnsureAttribute',
        'Invoke-IdleStepEnsureEntitlement',
        'Invoke-IdleStepCreateIdentity',
        'Invoke-IdleStepDisableIdentity',
        'Invoke-IdleStepEnableIdentity',
        'Invoke-IdleStepMoveIdentity',
        'Invoke-IdleStepDeleteIdentity'
    )

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Steps', 'Common', 'Builtin')
            LicenseUri    = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri    = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ReleaseNotes  = 'https://github.com/blindzero/IdentityLifecycleEngine/releases'
            ContactEmail  = '13959569+blindzero@users.noreply.github.com'
            RepositoryUrl = 'https://github.com/blindzero/IdentityLifecycleEngine'
            BugTrackerUrl = 'https://github.com/blindzero/IdentityLifecycleEngine/issues'
        }
    }
}
