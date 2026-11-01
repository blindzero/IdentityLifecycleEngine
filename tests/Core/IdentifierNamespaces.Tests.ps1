Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function New-NamespaceTestProvider {
        param(
            [Parameter(Mandatory)]
            [string[]] $Capabilities
        )

        $provider = [pscustomobject]@{ Name = 'NamespaceTestProvider' }
        $provider | Add-Member -MemberType NoteProperty -Name Advertised -Value $Capabilities
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { $this.Advertised } -Force
        return $provider
    }

    function New-NamespaceTestPlan {
        param(
            [Parameter(Mandatory)]
            [hashtable] $Providers
        )

        $wfPath = New-IdleTestWorkflowFile -FileName 'namespaces.psd1' -Content @'
@{
  Name           = 'Namespaces'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Hello' } }
  )
}
'@
        $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
        return New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $Providers
    }
}

Describe 'Identifier namespaces' {
    Context 'Rules (Get-IdleIdentifierNamespaceError)' {
        It '<Kind> <Identifier> (FirstParty: <FirstParty>) -> <Expected>' -ForEach @(
            @{ Kind = 'StepType'; Identifier = 'IdLE.Step.EmitEvent'; FirstParty = $true; Expected = $null }
            @{ Kind = 'StepType'; Identifier = 'IdLE.Step.Mailbox.GetInfo'; FirstParty = $true; Expected = $null }
            @{ Kind = 'StepType'; Identifier = 'IdLE.Foo.Bar'; FirstParty = $true; Expected = 'InvalidFirstPartyStepType' }
            @{ Kind = 'StepType'; Identifier = 'IdLE.Step'; FirstParty = $true; Expected = 'InvalidFirstPartyStepType' }
            @{ Kind = 'StepType'; Identifier = 'IdLE.Step.Foo'; FirstParty = $false; Expected = 'ReservedNamespace' }
            @{ Kind = 'StepType'; Identifier = 'idle.step.foo'; FirstParty = $false; Expected = 'ReservedNamespace' }
            @{ Kind = 'StepType'; Identifier = 'Contoso.IdLE.Step.Hr.SyncManager'; FirstParty = $false; Expected = $null }
            @{ Kind = 'StepType'; Identifier = 'Contoso.Step.Foo'; FirstParty = $false; Expected = 'InvalidExtensionNamespace' }
            @{ Kind = 'StepType'; Identifier = 'Contoso.IdLE.Hr.SyncManager'; FirstParty = $false; Expected = 'InvalidExtensionNamespace' }
            @{ Kind = 'StepType'; Identifier = 'EnsureMailbox'; FirstParty = $false; Expected = 'InvalidExtensionNamespace' }
            @{ Kind = 'Capability'; Identifier = 'IdLE.Identity.Read'; FirstParty = $false; Expected = $null }
            @{ Kind = 'Capability'; Identifier = 'IdLE.Mailbox.Read'; FirstParty = $false; Expected = $null }
            @{ Kind = 'Capability'; Identifier = 'IdLE.Hr.Manager.Read'; FirstParty = $false; Expected = 'UnknownCapability' }
            @{ Kind = 'Capability'; Identifier = 'Contoso.IdLE.Hr.Manager.Read'; FirstParty = $false; Expected = $null }
            @{ Kind = 'Capability'; Identifier = 'Contoso.IdLE.Read'; FirstParty = $false; Expected = 'InvalidExtensionNamespace' }
            @{ Kind = 'Capability'; Identifier = 'Contoso.Hr.Read'; FirstParty = $false; Expected = 'InvalidExtensionNamespace' }
        ) {
            InModuleScope 'IdLE.Core' -Parameters $_ {
                param($Kind, $Identifier, $FirstParty, $Expected)

                $namespaceError = Get-IdleIdentifierNamespaceError -Kind $Kind -Identifier $Identifier -FirstParty:$FirstParty

                if ($null -eq $Expected) {
                    $namespaceError | Should -BeNullOrEmpty
                }
                else {
                    $namespaceError | Should -BeLike "${Expected}:*"
                }
            }
        }
    }

    Context 'Provider capabilities' {
        It 'accepts IdLE-defined and extension capabilities' {
            $providers = @{ Hr = New-NamespaceTestProvider -Capabilities @('IdLE.Identity.Read', 'Contoso.IdLE.Hr.Manager.Read') }

            { New-NamespaceTestPlan -Providers $providers } | Should -Not -Throw
        }

        It 'rejects unknown IdLE.* capabilities (UnknownCapability)' {
            $providers = @{ Hr = New-NamespaceTestProvider -Capabilities @('IdLE.Hr.Manager.Read') }

            { New-NamespaceTestPlan -Providers $providers } | Should -Throw "*UnknownCapability: Capability 'IdLE.Hr.Manager.Read'*"
        }

        It 'rejects capabilities outside IdLE.* and Owner.IdLE.* (InvalidExtensionNamespace)' {
            $providers = @{ Hr = New-NamespaceTestProvider -Capabilities @('Contoso.Hr.Read') }

            { New-NamespaceTestPlan -Providers $providers } | Should -Throw "*InvalidExtensionNamespace: Capability 'Contoso.Hr.Read'*'Contoso.IdLE.Hr.Manager.Read'*"
        }
    }

    Context 'Host extension points' {
        It 'rejects IdLE.* step types in Providers.StepRegistry (ReservedNamespace)' {
            $plan = New-NamespaceTestPlan -Providers @{}

            { Invoke-IdlePlan -Plan $plan -Providers @{ StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-HostEmit' } } } |
                Should -Throw "*ReservedNamespace: Step type 'IdLE.Step.EmitEvent'*Providers.StepRegistry*"
        }

        It 'rejects host step types that do not follow Owner.IdLE.Step.* (InvalidExtensionNamespace)' {
            $providers = @{
                StepMetadata = @{
                    'Contoso.Step.Hr.Sync' = @{ WithSchema = @{ Keys = @{} } }
                }
            }

            { New-NamespaceTestPlan -Providers $providers } | Should -Throw "*InvalidExtensionNamespace: Step type 'Contoso.Step.Hr.Sync'*Providers.StepMetadata*"
        }
    }

    Context 'First-party detection' {
        It 'treats the bundled step packs as first-party' {
            InModuleScope 'IdLE.Core' {
                foreach ($name in @('IdLE.Steps.Common', 'IdLE.Steps.DirectorySync')) {
                    $module = Get-Module -Name $name -All | Select-Object -First 1
                    Test-IdleFirstPartyModule -Module $module | Should -BeTrue -Because $name
                }
            }
        }

        It 'does not treat a same-named module from another folder as first-party' {
            InModuleScope 'IdLE.Core' {
                $impostor = New-Module -Name 'IdLE.Steps.Common' -ScriptBlock { }
                Test-IdleFirstPartyModule -Module $impostor | Should -BeFalse
            }
        }
    }

    Context 'Capability catalog' {
        It 'documents exactly the IdLE-defined capabilities in docs/reference/capabilities.md' {
            $docPath = Join-Path -Path (Get-RepoRootPath) -ChildPath 'docs/reference/capabilities.md'
            $documented = @(
                Select-String -Path $docPath -Pattern '^#### `(IdLE\.[A-Za-z.]+)`' |
                    ForEach-Object { $_.Matches[0].Groups[1].Value } |
                    Sort-Object
            )

            $defined = InModuleScope 'IdLE.Core' { @((Get-IdleReservedNamespaces).Capability.Defined | Sort-Object) }

            $documented | Should -Be $defined
        }
    }
}
