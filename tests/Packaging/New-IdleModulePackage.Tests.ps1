Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')

    $script:RepoRoot = Get-RepoRootPath
    $script:PackageScript = Join-Path -Path $script:RepoRoot -ChildPath 'tools/New-IdleModulePackage.ps1'
    $script:SourceManifest = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE/IdLE.psd1'

    $script:BundledNames = @(
        (Import-PowerShellDataFile -Path $script:SourceManifest).NestedModules |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }
    )

    $script:PackageRoot = Join-Path -Path $TestDrive -ChildPath 'IdLE'
    $script:Package = & $script:PackageScript -OutputDirectory $script:PackageRoot -Clean
    $script:PackageManifest = Join-Path -Path $script:PackageRoot -ChildPath 'IdLE.psd1'
}

Describe 'New-IdleModulePackage (bundled IdLE package)' {
    Context 'Layout' {
        It 'Returns the package directory' {
            $script:Package.FullName | Should -Be (Get-Item -LiteralPath $script:PackageRoot).FullName
        }

        It 'Bundles all first-party modules under Modules/' {
            $script:BundledNames | Should -Contain 'IdLE.Core'
            $script:BundledNames | Should -Contain 'IdLE.Provider.AD'

            foreach ($name in $script:BundledNames) {
                Join-Path -Path $script:PackageRoot -ChildPath "Modules/$name/$name.psd1" | Should -Exist
            }
        }

        It 'Rewrites NestedModules to the in-package module paths' {
            $nested = @((Import-PowerShellDataFile -Path $script:PackageManifest).NestedModules)

            $nested | Should -Be @($script:BundledNames | ForEach-Object { ".\Modules\$_\$_.psd1" })
        }

        It 'Produces a valid module manifest' {
            { Test-ModuleManifest -Path $script:PackageManifest -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Import' {
        It 'Imports all bundled modules from the package and exports the provider factories' {
            $manifestEscaped = $script:PackageManifest -replace "'", "''"
            $script = @"
`$before = @(Get-Module -All | ForEach-Object Name)
Import-Module '$manifestEscaped' -ErrorAction Stop
`$idle = Get-Module -Name IdLE
[pscustomobject]@{
    ModuleBase = `$idle.ModuleBase
    Exported   = @(`$idle.ExportedCommands.Keys | Sort-Object)
    Nested     = @(Get-Module -All -Name 'IdLE.*' | ForEach-Object { [pscustomobject]@{ Name = `$_.Name; ModuleBase = `$_.ModuleBase } })
    # Modules from `$PSHOME (e.g. Microsoft.PowerShell.Utility) are auto-loaded built-ins, not dependencies.
    External   = @(Get-Module -All | Where-Object { `$before -notcontains `$_.Name -and `$_.Name -notlike 'IdLE*' -and -not `$_.ModuleBase.StartsWith(`$PSHOME) } | ForEach-Object Name)
} | ConvertTo-Json -Depth 4 -Compress
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -WorkingDirectory $TestDrive
            $result.ExitCode | Should -Be 0 -Because $result.StdErr

            $info = $result.StdOut | ConvertFrom-Json

            foreach ($name in $script:BundledNames) {
                $module = @($info.Nested | Where-Object Name -eq $name) | Select-Object -First 1
                $module | Should -Not -BeNullOrEmpty -Because "$name is part of the bundle"
                $module.ModuleBase | Should -Be ([System.IO.Path]::Combine($info.ModuleBase, 'Modules', $name))
            }

            foreach ($factory in @(
                    'New-IdleADIdentityProvider'
                    'New-IdleEntraIDIdentityProvider'
                    'New-IdleExchangeOnlineProvider'
                    'New-IdleEntraConnectDirectorySyncProvider'
                    'New-IdleMockIdentityProvider'
                )) {
                $info.Exported | Should -Contain $factory
            }

            @($info.External) | Should -BeNullOrEmpty -Because 'external dependencies must be loaded lazily'
        }
    }
}
