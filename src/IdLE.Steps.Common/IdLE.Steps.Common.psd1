@{
    RootModule        = 'IdLE.Steps.Common.psm1'
    ModuleVersion = '0.4.0'
    GUID              = '9bdf5e97-0344-4191-82ed-c534bd7cb9b5'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Common built-in steps for IdLE.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Invoke-IdleStepEmitEvent',
        'Invoke-IdleStepEnsureAttribute',
        'Invoke-IdleStepEnsureEntitlement'
    )

    PrivateData       = @{
        PSData = @{
            Tags       = @('Identity Lifecycle Engine', 'IdLE', 'Steps')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
