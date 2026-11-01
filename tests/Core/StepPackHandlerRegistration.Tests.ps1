Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    Import-IdleTestMailboxModule

    $script:PackName = 'Contoso.IdLE.Steps.Hr'
    $script:StepType = 'Contoso.IdLE.Step.Hr.Hello'

    # Creates a step pack module on disk. With -NoMarker the module has no PrivateData.IdLE marker and instead
    # exports Get-IdleStepMetadataCatalog (the removed name-based discovery shape).
    function New-TestStepPack {
        param(
            [Parameter(Mandatory)]
            [string] $CatalogContent,

            [Parameter()]
            [string] $StepCatalog = 'StepMetadataCatalog.psd1',

            [Parameter()]
            [string] $PackName = $script:PackName,

            [Parameter()]
            [switch] $NoMarker
        )

        $marker = if ($NoMarker) { '' } else { "IdLE = @{ Kind = 'StepPack'; StepCatalog = '$StepCatalog' }" }
        $exports = if ($NoMarker) { "'Invoke-ContosoStepHello', 'Get-IdleStepMetadataCatalog'" } else { "'Invoke-ContosoStepHello'" }

        $moduleDir = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N')) | Join-Path -ChildPath $PackName
        $null = New-Item -Path $moduleDir -ItemType Directory -Force

        Set-Content -Path (Join-Path $moduleDir "$($PackName).psm1") -Encoding UTF8 -Value @'
function Invoke-ContosoStepHello {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Context,
        [Parameter(Mandatory)] [hashtable] $With,
        [Parameter(Mandatory)] [object] $Step
    )

    $Context.EventSink.WriteEvent('Test.IdLE.StepPack.Hello', 'Hello from step pack', $Step.Name, @{})

    return $null
}

function Get-IdleStepMetadataCatalog {
    return Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'StepMetadataCatalog.psd1')
}

Export-ModuleMember -Function 'Invoke-ContosoStepHello', 'Get-IdleStepMetadataCatalog'
'@

        Set-Content -Path (Join-Path $moduleDir "$PackName.psd1") -Encoding UTF8 -Value @"
@{
    RootModule        = '$PackName.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '$([guid]::NewGuid())'
    FunctionsToExport = @($exports)
    PrivateData       = @{ $marker }
}
"@

        Set-Content -Path (Join-Path $moduleDir 'StepMetadataCatalog.psd1') -Encoding UTF8 -Value $CatalogContent

        Import-Module -Name (Join-Path $moduleDir "$PackName.psd1") -Force -ErrorAction Stop
    }

    function New-TestCatalogContent {
        param(
            [Parameter(Mandatory)]
            [string] $HandlerLiteral,

            [Parameter()]
            [string] $StepType = $script:StepType
        )

        return @"
@{
    '$StepType' = @{
        Handler              = $HandlerLiteral
        RequiredCapabilities = @()
        WithSchema           = @{
            Keys = @{}
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
        Remove-Module -Name $script:PackName, 'IdLE.Steps.Impostor', 'IdLE.Steps.Legacy' -Force -ErrorAction SilentlyContinue
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

        It 'rejects Providers.StepRegistry entries for step pack step types (DuplicateStepHandler)' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            InModuleScope 'IdLE.Core' -Parameters @{ StepType = $script:StepType } {
                param($StepType)
                { Get-IdleStepRegistry -Providers @{ StepRegistry = @{ $StepType = 'Invoke-HostHello' } } } |
                    Should -Throw '*DuplicateStepHandler*'
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
                        WithSchema           = @{ Keys = @{} }
                    }
                }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } | Should -Throw '*Providers.StepRegistry*'
        }
    }

    Context 'Identifier namespaces and discovery' {
        It 'rejects IdLE.* step types from a third-party step pack (ReservedNamespace)' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'" -StepType 'IdLE.Step.Hr.Hello')

            { New-TestPlan } | Should -Throw "*ReservedNamespace: Step type 'IdLE.Step.Hr.Hello'*'<Owner>.IdLE.Step.Hr.Hello'*"
        }

        It 'rejects step types that do not follow Owner.IdLE.Step.* (InvalidExtensionNamespace)' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'" -StepType 'Contoso.Step.Hr.Hello')

            { New-TestPlan } | Should -Throw "*InvalidExtensionNamespace: Step type 'Contoso.Step.Hr.Hello'*"
        }

        It 'does not treat a module as first-party because of its IdLE.* name' {
            New-TestStepPack -PackName 'IdLE.Steps.Impostor' -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'" -StepType 'IdLE.Step.Impostor.Hello')

            { New-TestPlan } | Should -Throw "*ReservedNamespace*Defined by step pack 'IdLE.Steps.Impostor'*"
        }

        It 'does not discover IdLE.Steps.* modules without the manifest marker' {
            New-TestStepPack -PackName 'IdLE.Steps.Legacy' -NoMarker -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            { New-TestPlan } | Should -Throw "*MissingStepTypeMetadata*"
        }

        It 'rejects host metadata for a third-party step pack step type (DuplicateStepTypeMetadata)' {
            New-TestStepPack -CatalogContent (New-TestCatalogContent -HandlerLiteral "'Invoke-ContosoStepHello'")

            InModuleScope 'IdLE.Core' -Parameters @{ StepType = $script:StepType } {
                param($StepType)
                $providers = @{ StepMetadata = @{ $StepType = @{ WithSchema = @{ Keys = @{} } } } }
                { Resolve-IdleStepMetadataCatalog -Providers $providers } | Should -Throw "*DuplicateStepTypeMetadata*Contoso.IdLE.Steps.Hr*"
            }
        }

        It 'accepts extension capabilities and rejects unknown IdLE.* capabilities in step pack metadata' {
            $catalog = @"
@{
    '$($script:StepType)' = @{
        Handler              = 'Invoke-ContosoStepHello'
        RequiredCapabilities = @('IdLE.Identity.Read', 'Contoso.IdLE.Hr.Manager.Read')
        WithSchema           = @{ Keys = @{} }
    }
    'Contoso.IdLE.Step.Hr.Unknown' = @{
        Handler              = 'Invoke-ContosoStepHello'
        RequiredCapabilities = @('IdLE.Hr.Manager.Read')
        WithSchema           = @{ Keys = @{} }
    }
}
"@
            New-TestStepPack -CatalogContent $catalog

            { New-TestPlan } | Should -Throw "*UnknownCapability: Capability 'IdLE.Hr.Manager.Read'*Contoso.IdLE.Step.Hr.Unknown*"
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
