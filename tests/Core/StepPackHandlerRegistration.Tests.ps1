Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    Import-IdleTestMailboxModule

    $script:PackName = 'Contoso.IdLE.Steps.Hr'
    $script:StepType = 'Contoso.IdLE.Step.Hr.Hello'

    # Creates a step pack module on disk that is discovered via the manifest marker only
    # (its name does not match 'IdLE.Steps.*' and it exports no Get-IdleStepMetadataCatalog).
    function New-TestStepPack {
        param(
            [Parameter(Mandatory)]
            [string] $CatalogContent,

            [Parameter()]
            [string] $StepCatalog = 'StepMetadataCatalog.psd1'
        )

        $moduleDir = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N')) | Join-Path -ChildPath $script:PackName
        $null = New-Item -Path $moduleDir -ItemType Directory -Force

        Set-Content -Path (Join-Path $moduleDir "$($script:PackName).psm1") -Encoding UTF8 -Value @'
function Invoke-ContosoStepHello {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Context,
        [Parameter(Mandatory)] [object] $Step
    )

    $Context.EventSink.WriteEvent('Custom', 'Hello from step pack', $Step.Name, @{})

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Error      = $null
    }
}

Export-ModuleMember -Function 'Invoke-ContosoStepHello'
'@

        Set-Content -Path (Join-Path $moduleDir "$($script:PackName).psd1") -Encoding UTF8 -Value @"
@{
    RootModule        = '$($script:PackName).psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '$([guid]::NewGuid())'
    FunctionsToExport = @('Invoke-ContosoStepHello')
    PrivateData       = @{
        IdLE = @{
            Kind        = 'StepPack'
            StepCatalog = '$StepCatalog'
        }
    }
}
"@

        Set-Content -Path (Join-Path $moduleDir 'StepMetadataCatalog.psd1') -Encoding UTF8 -Value $CatalogContent

        Import-Module -Name (Join-Path $moduleDir "$($script:PackName).psd1") -Force -ErrorAction Stop
    }

    function New-TestCatalogContent {
        param(
            [Parameter(Mandatory)]
            [string] $HandlerLiteral
        )

        return @"
@{
    '$($script:StepType)' = @{
        Handler              = $HandlerLiteral
        RequiredCapabilities = @()
        WithSchema           = @{
            RequiredKeys = @()
            OptionalKeys = @()
        }
    }
}
"@
    }

    function New-TestPlan {
        $wfPath = New-IdleTestWorkflowFile -FileName 'step-pack-handler.psd1' -Content @"
@{
  Name           = 'Step pack handler'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Hello'; Type = '$($script:StepType)' }
  )
}
"@
        $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
        return New-IdlePlan -WorkflowPath $wfPath -Request $req
    }
}

Describe 'Step pack handler registration (StepMetadataCatalog Handler)' {
    AfterEach {
        Remove-Module -Name $script:PackName -Force -ErrorAction SilentlyContinue
    }

    Context 'Third-party step pack with manifest marker' {
        It 'executes the catalog handler without Providers.StepRegistry' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            $result = Invoke-IdlePlan -Plan (New-TestPlan) -Providers @{}

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
            ($result.Events | Where-Object Message -eq 'Hello from step pack').Count | Should -Be 1
        }

        It 'binds an unqualified handler name to the declaring module' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            InModuleScope 'IdLE.Core' -Parameters @{ StepType = $script:StepType } {
                param($StepType)
                $registry = Get-IdleStepRegistry -Providers $null
                $registry[$StepType] | Should -Be 'Contoso.IdLE.Steps.Hr\Invoke-ContosoStepHello'
            }
        }

        It 'lets Providers.StepRegistry override the catalog handler' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            InModuleScope 'IdLE.Core' -Parameters @{ StepType = $script:StepType } {
                param($StepType)
                $registry = Get-IdleStepRegistry -Providers @{ StepRegistry = @{ $StepType = 'Invoke-HostHello' } }
                $registry[$StepType] | Should -Be 'Invoke-HostHello'
            }
        }
    }

    Context 'Validation' {
        It 'rejects a handler from another module' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'IdLE.Steps.Common\Invoke-IdleStepEmitEvent'")

            { New-TestPlan } | Should -Throw '*outside of its own module*'
        }

        It 'rejects a non-string handler' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "@('Invoke-ContosoStepHello')")

            { New-TestPlan } | Should -Throw "*invalid 'Handler'*"
        }

        It 'rejects a StepCatalog path outside of the module folder' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'") -StepCatalog '..\StepMetadataCatalog.psd1'

            { New-TestPlan } | Should -Throw '*outside of its module folder*'
        }

        It 'rejects a missing StepCatalog file' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'") -StepCatalog 'Missing.psd1'

            { New-TestPlan } | Should -Throw '*was not found*'
        }

        It 'rejects Handler in host-provided Providers.StepMetadata' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'host-handler.psd1' -Content @'
@{
  Name           = 'Host handler'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Hello'; Type = 'Test.IdLE.Step.Hello' }
  )
}
'@
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                StepMetadata = @{
                    'Test.IdLE.Step.Hello' = @{
                        Handler              = 'Invoke-HostHello'
                        RequiredCapabilities = @()
                        WithSchema           = @{ RequiredKeys = @(); OptionalKeys = @() }
                    }
                }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } | Should -Throw '*Providers.StepRegistry*'
        }
    }

    Context 'First-party step packs' {
        It 'declares a resolvable handler for every built-in step type' {
            InModuleScope 'IdLE.Core' {
                $catalog = Resolve-IdleStepMetadataCatalog -Providers $null
                $registry = Get-IdleStepRegistry -Providers $null

                $builtInTypes = @($catalog.Keys | Where-Object { $_ -like 'IdLE.Step.*' })
                $builtInTypes.Count | Should -Be 16

                foreach ($stepType in $builtInTypes) {
                    $catalog[$stepType].Handler | Should -Match '^IdLE\.Steps\.(Common|DirectorySync|Mailbox)\\Invoke-IdleStep' -Because $stepType
                    Resolve-IdleStepHandler -StepType $stepType -StepRegistry $registry | Should -Not -BeNullOrEmpty -Because $stepType
                }
            }
        }
    }
}
