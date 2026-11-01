Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleContractTestHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [hashtable] $With
        )

        $global:IdleContractTestLastWith = $With
        if ($With.ContainsKey('Output')) {
            return $With.Output
        }
        return $null
    }

    function global:Invoke-IdleContractTestProviderHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [hashtable] $With,
            [Parameter(Mandatory)] [object] $Provider
        )

        $global:IdleContractTestLastWith = $With
        $result = $Provider.Invoke('Echo', @($With.Value))
        return @{ Changed = $true; Data = @{ Echo = $result } }
    }

    function global:Invoke-IdleContractTestLegacyHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [object] $Step
        )

        return $null
    }

    function global:Invoke-IdleContractTestNoContextHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [hashtable] $With
        )

        return $null
    }

    function global:Invoke-IdleContractTestOutputHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [hashtable] $With
        )

        'leaked'
        return @{ Changed = $true }
    }

    function New-ContractEchoProvider {
        param([switch] $WithEventSink)

        $provider = [pscustomobject]@{ Sessions = [System.Collections.Generic.List[object]]::new() }
        if ($WithEventSink) {
            $provider | Add-Member -MemberType NoteProperty -Name EventSink -Value $null
        }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { @() }
        $provider | Add-Member -MemberType ScriptMethod -Name Echo -Value {
            param($Value, $AuthSession)
            $this.Sessions.Add($AuthSession)
            return "$Value|$AuthSession"
        }
        $provider | Add-Member -MemberType ScriptMethod -Name ListWithKind -Value {
            param($IdentityKey, $AuthSession, $Kind)
            return "$IdentityKey|$AuthSession|$Kind"
        }
        $provider | Add-Member -MemberType ScriptMethod -Name ListWithKindLowerCase -Value {
            param($IdentityKey, $authsession, $Kind)
            return "$IdentityKey|$authsession|$Kind"
        }
        $provider | Add-Member -MemberType ScriptMethod -Name NoAuth -Value {
            param($Value)
            return "$Value"
        }
        return $provider
    }

    function New-ContractBroker {
        $broker = [pscustomobject]@{ Calls = 0 }
        $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            $this.Calls++
            return "session-$Name"
        }
        return $broker
    }

    function Invoke-ContractWorkflow {
        param(
            [Parameter(Mandatory)] [string] $With,
            [Parameter()] [string] $Handler = 'Invoke-IdleContractTestProviderHandler',
            [Parameter()] [hashtable] $Metadata,
            [Parameter()] [hashtable] $ExtraProviders = @{}
        )

        if ($null -eq $Metadata) {
            $Metadata = @{
                RequiredCapabilities = @()
                Provider             = @{ DefaultAlias = 'Echo' }
                WithSchema           = @{ Keys = @{ Value = @{ Type = 'String'; Required = $true } } }
            }
        }

        $wfPath = New-IdleTestWorkflowFile -FileName 'step-contract.psd1' -Content @"
@{
  Name           = 'Contract'
  LifecycleEvent = 'Joiner'
  Steps          = @( @{ Name = 'S1'; Type = 'Test.IdLE.Step.Contract'; With = $With } )
}
"@
        $providers = @{
            StepRegistry      = @{ 'Test.IdLE.Step.Contract' = $Handler }
            StepMetadata      = @{ 'Test.IdLE.Step.Contract' = $Metadata }
            AuthSessionBroker = (New-ContractBroker)
        }
        foreach ($key in $ExtraProviders.Keys) { $providers[$key] = $ExtraProviders[$key] }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request (New-IdleTestRequest -LifecycleEvent 'Joiner') -Providers $providers
        return [pscustomobject]@{
            Plan      = $plan
            Result    = Invoke-IdlePlan -Plan $plan -Providers $providers
            Providers = $providers
        }
    }
}

AfterAll {
    foreach ($name in @('Invoke-IdleContractTestHandler', 'Invoke-IdleContractTestProviderHandler', 'Invoke-IdleContractTestLegacyHandler', 'Invoke-IdleContractTestNoContextHandler', 'Invoke-IdleContractTestOutputHandler')) {
        Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name 'IdleContractTestLastWith' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Step contract' {
    Context 'With validation (ConvertTo-IdleSchemaValue)' {
        It '<Case> -> <Expected>' -ForEach @(
            @{ Case = 'missing required key'; Schema = @{ Type = 'Hashtable'; Keys = @{ A = @{ Type = 'String'; Required = $true } } }; Value = @{}; Expected = 'WithKeyMissing' }
            @{ Case = 'required key set to null'; Schema = @{ Type = 'Hashtable'; Keys = @{ A = @{ Type = 'String'; Required = $true } } }; Value = @{ A = $null }; Expected = 'WithKeyMissing' }
            @{ Case = 'unknown key'; Schema = @{ Type = 'Hashtable'; Keys = @{ A = @{ Type = 'String' } } }; Value = @{ B = 'x' }; Expected = 'WithKeyUnknown' }
            @{ Case = 'string expected, int given'; Schema = @{ Type = 'String' }; Value = 1; Expected = 'WithKeyTypeMismatch' }
            @{ Case = 'int expected, string given (no coercion)'; Schema = @{ Type = 'Int' }; Value = '600'; Expected = 'WithKeyTypeMismatch' }
            @{ Case = 'bool expected, string given (no coercion)'; Schema = @{ Type = 'Bool' }; Value = 'true'; Expected = 'WithKeyTypeMismatch' }
            @{ Case = 'array expected, string given'; Schema = @{ Type = 'Array' }; Value = 'x'; Expected = 'WithKeyTypeMismatch' }
            @{ Case = 'hashtable expected, array given'; Schema = @{ Type = 'Hashtable' }; Value = @(1); Expected = 'WithKeyTypeMismatch' }
            @{ Case = 'empty string'; Schema = @{ Type = 'String' }; Value = ''; Expected = 'WithValueNotAllowed' }
            @{ Case = 'empty array'; Schema = @{ Type = 'Array' }; Value = @(); Expected = 'WithValueNotAllowed' }
            @{ Case = 'value not allowed'; Schema = @{ Type = 'String'; AllowedValues = @('Present', 'Absent') }; Value = 'Maybe'; Expected = 'WithValueNotAllowed' }
        ) {
            InModuleScope 'IdLE.Core' -Parameters $_ {
                param($Schema, $Value, $Expected)
                { ConvertTo-IdleSchemaValue -Schema $Schema -Value $Value -Path 'With' -ErrorPrefix 'Step' } |
                    Should -Throw -ExpectedMessage "${Expected}:*"
            }
        }

        It 'reports the full path of nested keys and array items' {
            InModuleScope 'IdLE.Core' {
                $schema = @{
                    Type = 'Hashtable'
                    Keys = @{
                        Entitlement = @{ Type = 'Hashtable'; Keys = @{ Kind = @{ Type = 'String'; Required = $true } } }
                        Keep        = @{ Type = 'Array'; Items = @{ Type = 'Hashtable'; Keys = @{ Id = @{ Type = 'String'; Required = $true } } } }
                    }
                }

                { ConvertTo-IdleSchemaValue -Schema $schema -Value @{ Entitlement = @{} } -Path 'With' -ErrorPrefix 'Step' } |
                    Should -Throw -ExpectedMessage '*With.Entitlement.Kind is required*'
                { ConvertTo-IdleSchemaValue -Schema $schema -Value @{ Keep = @(@{ Id = 'a' }, @{}) } -Path 'With' -ErrorPrefix 'Step' } |
                    Should -Throw -ExpectedMessage '*With.Keep`[1`].Id is required*'
            }
        }

        It 'applies defaults, normalizes allowed values and treats optional nulls as absent' {
            InModuleScope 'IdLE.Core' {
                $schema = @{
                    Type = 'Hashtable'
                    Keys = @{
                        State   = @{ Type = 'String'; AllowedValues = @('Present', 'Absent'); Default = 'Present' }
                        Wait    = @{ Type = 'Bool'; Default = $false }
                        Mode    = @{ Type = 'String'; AllowedValues = @('Present', 'Absent') }
                        Comment = @{ Type = 'String' }
                    }
                }

                $result = ConvertTo-IdleSchemaValue -Schema $schema -Value @{ Mode = 'absent'; Comment = $null } -Path 'With' -ErrorPrefix 'Step'

                $result.State | Should -Be 'Present'
                $result.Wait | Should -BeFalse
                $result.Mode | Should -BeExactly 'Absent'
                $result.ContainsKey('Comment') | Should -BeFalse
            }
        }

        It 'keeps a single-element array an array through planning (regression)' {
            $run = Invoke-ContractWorkflow -Handler 'Invoke-IdleContractTestHandler' -With "@{ Items = @('only') }" -Metadata @{
                RequiredCapabilities = @()
                WithSchema           = @{ Keys = @{ Items = @{ Type = 'Array'; Items = @{ Type = 'String' } } } }
            }

            $run.Result.Status | Should -Be 'Completed'
            , $run.Plan.Steps[0].With.Items | Should -BeOfType ([object[]])
            @($run.Plan.Steps[0].With.Items).Count | Should -Be 1
        }
    }

    Context 'Catalog contract (Assert-IdleStepMetadataContract)' {
        It '<Case> -> <Expected>' -ForEach @(
            @{ Case = 'legacy RequiredKeys/OptionalKeys'; Metadata = @{ WithSchema = @{ RequiredKeys = @(); OptionalKeys = @() } }; Expected = 'LegacyWithSchema' }
            @{ Case = 'missing WithSchema'; Metadata = @{}; Expected = 'InvalidWithSchema' }
            @{ Case = 'missing Keys'; Metadata = @{ WithSchema = @{} }; Expected = 'InvalidWithSchema' }
            @{ Case = 'unknown type'; Metadata = @{ WithSchema = @{ Keys = @{ A = @{ Type = 'Guid' } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'unknown key schema property'; Metadata = @{ WithSchema = @{ Keys = @{ A = @{ Type = 'String'; Min = 1 } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'Required and Default'; Metadata = @{ WithSchema = @{ Keys = @{ A = @{ Type = 'String'; Required = $true; Default = 'x' } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'Default not matching Type'; Metadata = @{ WithSchema = @{ Keys = @{ A = @{ Type = 'Int'; Default = 'x' } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'AllowedValues on Bool'; Metadata = @{ WithSchema = @{ Keys = @{ A = @{ Type = 'Bool'; AllowedValues = @($true) } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'common key declared in Keys'; Metadata = @{ WithSchema = @{ Keys = @{ Provider = @{ Type = 'String' } } } }; Expected = 'InvalidWithSchema' }
            @{ Case = 'invalid Provider entry'; Metadata = @{ Provider = @{ Alias = 'x' }; WithSchema = @{ Keys = @{} } }; Expected = 'InvalidWithSchema' }
        ) {
            InModuleScope 'IdLE.Core' -Parameters $_ {
                param($Metadata, $Expected)
                { Assert-IdleStepMetadataContract -Metadata $Metadata -StepType 'Test.IdLE.Step.X' -SourceName 'Test' } |
                    Should -Throw -ExpectedMessage "${Expected}:*"
            }
        }

        It 'accepts all first-party catalogs' {
            InModuleScope 'IdLE.Core' {
                $catalog = Resolve-IdleStepMetadataCatalog -Providers $null
                $catalog.Count | Should -BeGreaterThan 10
            }
        }
    }

    Context 'Common keys and provider resolution' {
        It 'rejects common keys for steps without Provider, even with AllowAdditionalKeys' {
            { Invoke-ContractWorkflow -Handler 'Invoke-IdleContractTestHandler' -With "@{ Provider = 'Echo' }" -Metadata @{
                    RequiredCapabilities = @()
                    WithSchema           = @{ Keys = @{}; AllowAdditionalKeys = $true }
                } } | Should -Throw -ExpectedMessage '*WithKeyUnknown*With.Provider*'
        }

        It 'applies the default provider alias in the plan and hides common keys from the handler' {
            $run = Invoke-ContractWorkflow -With "@{ Value = 'v' }" -ExtraProviders @{ Echo = (New-ContractEchoProvider) }

            $run.Plan.Steps[0].With.Provider | Should -Be 'Echo'
            $run.Result.Status | Should -Be 'Completed'
            $global:IdleContractTestLastWith.ContainsKey('Provider') | Should -BeFalse
        }

        It 'fails the step with ProviderNotSupplied when the alias is missing' {
            $run = Invoke-ContractWorkflow -With "@{ Value = 'v'; Provider = 'Missing' }" -ExtraProviders @{ Echo = (New-ContractEchoProvider) }

            $run.Result.Status | Should -Be 'Failed'
            $run.Result.Steps[0].Error | Should -BeLike 'ProviderNotSupplied:*Missing*'
        }

        It 'names the auth session after the alias when the step declares AuthSessionNameFromAlias' {
            InModuleScope 'IdLE.Core' {
                $metadata = @{ Provider = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }; WithSchema = @{ Keys = @{} } }

                (ConvertTo-IdleStepWith -Metadata $metadata -With @{} -StepName 'S' -StepType 'T').AuthSessionName | Should -Be 'ExchangeOnline'
                (ConvertTo-IdleStepWith -Metadata $metadata -With @{ Provider = 'Exo2' } -StepName 'S' -StepType 'T').AuthSessionName | Should -Be 'Exo2'
                (ConvertTo-IdleStepWith -Metadata $metadata -With @{ AuthSessionName = 'Admin' } -StepName 'S' -StepType 'T').AuthSessionName | Should -Be 'Admin'
            }
        }
    }

    Context 'Handler signature' {
        It '<Handler> -> <Expected>' -ForEach @(
            @{ Handler = 'Invoke-IdleContractTestLegacyHandler'; Expected = 'LegacyStepHandler' }
            @{ Handler = 'Invoke-IdleContractTestNoContextHandler'; Expected = 'InvalidStepHandlerSignature' }
            @{ Handler = 'Invoke-IdleContractTestHandler'; Expected = 'InvalidStepHandlerSignature' }
        ) {
            # The step declares a Provider, so Invoke-IdleContractTestHandler lacks -Provider.
            $run = Invoke-ContractWorkflow -Handler $Handler -With "@{ Value = 'v' }" -ExtraProviders @{ Echo = (New-ContractEchoProvider) }

            $run.Result.Status | Should -Be 'Failed'
            $run.Result.Steps[0].Error | Should -BeLike "${Expected}:*"
        }

        It 'rejects -Provider on a handler whose step declares no Provider' {
            $run = Invoke-ContractWorkflow -With "@{ Value = 'v' }" -Metadata @{
                RequiredCapabilities = @()
                WithSchema           = @{ Keys = @{ Value = @{ Type = 'String' } } }
            }

            $run.Result.Steps[0].Error | Should -BeLike 'InvalidStepHandlerSignature:*declares -Provider*'
        }
    }

    Context 'Handler result' {
        It 'builds IdLE.StepResult from the handler hashtable' {
            $run = Invoke-ContractWorkflow -With "@{ Value = 'v' }" -ExtraProviders @{ Echo = (New-ContractEchoProvider) }

            $step = $run.Result.Steps[0]
            $step.PSTypeNames | Should -Contain 'IdLE.StepResult'
            $step.Changed | Should -BeTrue
            $step.Data.Echo | Should -Be 'v|session-'
            $step.Attempts | Should -Be 1
        }

        It '<Case> -> InvalidStepHandlerResult' -ForEach @(
            @{ Case = 'unknown key'; Output = "@{ Status = 'Failed' }" }
            @{ Case = 'non-bool Changed'; Output = "@{ Changed = 'yes' }" }
            @{ Case = 'non-hashtable Data'; Output = "@{ Data = 'x' }" }
            @{ Case = 'non-hashtable result'; Output = "'done'" }
        ) {
            $run = Invoke-ContractWorkflow -Handler 'Invoke-IdleContractTestHandler' -With "@{ Output = $Output }" -Metadata @{
                RequiredCapabilities = @()
                WithSchema           = @{ Keys = @{ Output = @{ Type = 'Any' } } }
            }

            $run.Result.Steps[0].Status | Should -Be 'Failed'
            $run.Result.Steps[0].Error | Should -BeLike 'InvalidStepHandlerResult:*'
        }

        It 'rejects handlers that leak pipeline output' {
            $run = Invoke-ContractWorkflow -Handler 'Invoke-IdleContractTestOutputHandler' -With '@{}' -Metadata @{
                RequiredCapabilities = @()
                WithSchema           = @{ Keys = @{} }
            }

            $run.Result.Steps[0].Error | Should -BeLike 'InvalidStepHandlerResult:*wrote 2 objects*'
        }
    }

    Context 'Provider handle (New-IdleProviderHandle)' {
        BeforeEach {
            $script:EchoProvider = New-ContractEchoProvider -WithEventSink
            $script:Broker = New-ContractBroker
            $script:Context = [pscustomobject]@{
                Providers = @{ Echo = $script:EchoProvider }
                EventSink = New-IdleTestEventSink
            }
            $broker = $script:Broker
            $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $broker.AcquireAuthSession($Name, $Options)
            }.GetNewClosure()
        }

        It 'passes a single argument plus the auth session intact (regression)' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo' -AuthSessionName 'Admin'
                $handle.Invoke('Echo', @('user@contoso.com')) | Should -Be 'user@contoso.com|session-Admin'
            }
        }

        It 'inserts the auth session at its declared position' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo' -AuthSessionName 'Admin'
                $handle.Invoke('ListWithKind', @('user1', 'Group')) | Should -Be 'user1|session-Admin|Group'
            }
        }

        It 'matches the AuthSession parameter name case-insensitively (regression)' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo' -AuthSessionName 'Admin'
                $handle.Invoke('ListWithKindLowerCase', @('user1', 'Group')) | Should -Be 'user1|session-Admin|Group'
            }
        }

        It 'acquires the auth session once per handle' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo' -AuthSessionName 'Admin'
                $null = $handle.Invoke('Echo', @('a'))
                $null = $handle.Invoke('Echo', @('b'))
            }

            $script:Broker.Calls | Should -Be 1
        }

        It 'does not acquire a session for methods without AuthSession when no AuthSessionName is set' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo'
                $handle.Invoke('NoAuth', @('a')) | Should -Be 'a'
            }

            $script:Broker.Calls | Should -Be 0
        }

        It 'reports methods and parameters and rejects unknown methods' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $handle = New-IdleProviderHandle -Context $Context -Alias 'Echo'

                $handle.Alias | Should -Be 'Echo'
                $handle.HasMethod('Echo') | Should -BeTrue
                $handle.HasMethod('Missing') | Should -BeFalse
                $handle.HasParameter('ListWithKind', 'Kind') | Should -BeTrue
                $handle.HasParameter('Echo', 'Kind') | Should -BeFalse
                { $handle.Invoke('Missing', @()) } | Should -Throw -ExpectedMessage '*ProviderMethodNotImplemented*Missing*'
            }
        }

        It 'wires the run event sink into providers that expose EventSink' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                $null = New-IdleProviderHandle -Context $Context -Alias 'Echo'
            }

            $script:EchoProvider.EventSink | Should -Be $script:Context.EventSink
        }

        It 'throws ProviderNotSupplied for unknown aliases' {
            InModuleScope 'IdLE.Core' -Parameters @{ Context = $script:Context } {
                param($Context)
                { New-IdleProviderHandle -Context $Context -Alias 'Nope' } | Should -Throw -ExpectedMessage 'ProviderNotSupplied:*'
            }
        }
    }
}
