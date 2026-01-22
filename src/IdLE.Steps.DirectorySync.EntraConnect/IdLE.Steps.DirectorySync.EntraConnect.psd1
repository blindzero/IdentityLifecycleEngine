@{
    RootModule        = 'IdLE.Steps.DirectorySync.EntraConnect.psm1'
    ModuleVersion = '0.8.0'
    GUID              = 'b2c3d4e5-6f78-9012-bcde-f12345678901'
    Author            = 'Matthias Fleschuetz'
    Copyright         = '(c) Matthias Fleschuetz. All rights reserved.'
    Description       = 'Entra Connect directory sync steps for IdLE.'
    PowerShellVersion = '7.0'

    RequiredModules   = @(
        '..\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
    )

    FunctionsToExport = @(
        'Invoke-IdleStepTriggerDirectorySync'
    )

    PrivateData       = @{
        PSData = @{
            Tags       = @('IdentityLifecycleEngine', 'IdLE', 'Steps', 'DirectorySync', 'EntraConnect')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
            ProjectUri = 'https://github.com/blindzero/IdentityLifecycleEngine'
            ContactEmail = '13959569+blindzero@users.noreply.github.com'
        }
    }
}
