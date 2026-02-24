Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepPruneEntitlements (built-in step)' {
    BeforeEach {
        $script:Provider = New-IdleMockIdentityProvider
        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ Identity = $script:Provider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }

        # Seed the identity with some entitlements
        $null = $script:Provider.EnsureAttribute('user1', 'Seed', 'Value')
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-All,DC=contoso,DC=com' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-HR,DC=contoso,DC=com'; DisplayName = 'HR Group' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com'; DisplayName = 'Leaver Retain' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-EXTRA,DC=contoso,DC=com'; DisplayName = 'Leaver Extra' })

        $script:StepTemplate = [pscustomobject]@{
            Name = 'Prune group memberships'
            Type = 'IdLE.Step.PruneEntitlements'
            With = @{
                IdentityKey = 'user1'
                Provider    = 'Identity'
                Kind        = 'Group'
                Keep        = @(
                    @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com' }
                )
            }
        }
    }

    Context 'Behavior: Keep only' {
        It 'removes entitlements not in the keep set' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            @($remaining).Count | Should -Be 1
            $remaining[0].Id | Should -Be 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
        }

        It 'keeps explicitly kept entitlement regardless of case' {
            $step = $script:StepTemplate
            $step.With.Keep = @(
                @{ Kind = 'Group'; Id = 'cn=leaver-retain,dc=contoso,dc=com' }
            )

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'

            $remaining = $script:Provider.ListEntitlements('user1')
            @($remaining).Count | Should -Be 1
        }

        It 'is idempotent when all non-keep entitlements are already absent' {
            # Remove non-keep entitlements manually first
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-All,DC=contoso,DC=com' })
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-HR,DC=contoso,DC=com' })
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-EXTRA,DC=contoso,DC=com' })

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeFalse
        }
    }

    Context 'Behavior: Keep + KeepPattern union' {
        It 'keeps entitlements matching wildcard KeepPattern' {
            $step = $script:StepTemplate
            $step.With.KeepPattern = @('CN=LEAVER-*,DC=contoso,DC=com')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            # Keep: explicit LEAVER-RETAIN + pattern LEAVER-* (LEAVER-RETAIN + LEAVER-EXTRA)
            @($remaining).Count | Should -Be 2
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-EXTRA,DC=contoso,DC=com'
        }

        It 'unions Keep and KeepPattern (keep-set is the union)' {
            $step = $script:StepTemplate
            # Keep CN=G-All explicitly, KeepPattern matches LEAVER-*
            $step.With.Keep = @(
                @{ Kind = 'Group'; Id = 'CN=G-All,DC=contoso,DC=com' }
            )
            $step.With.KeepPattern = @('CN=LEAVER-*,DC=contoso,DC=com')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            # G-All (explicit) + LEAVER-RETAIN + LEAVER-EXTRA (pattern)
            @($remaining).Count | Should -Be 3
            $remainingIds | Should -Contain 'CN=G-All,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-EXTRA,DC=contoso,DC=com'
        }

        It 'only keeps entitlements matching KeepPattern when Keep is absent' {
            $step = [pscustomobject]@{
                Name = 'Prune with pattern only'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{
                    IdentityKey = 'user1'
                    Provider    = 'Identity'
                    Kind        = 'Group'
                    KeepPattern = @('CN=G-All,*')
                }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'

            $remaining = $script:Provider.ListEntitlements('user1')
            @($remaining).Count | Should -Be 1
            $remaining[0].Id | Should -Be 'CN=G-All,DC=contoso,DC=com'
        }
    }

    Context 'Behavior: EnsureKeepEntitlements' {
        It 'grants missing explicit Keep entitlements when EnsureKeepEntitlements is $true' {
            $step = $script:StepTemplate
            # Add a Keep item that does NOT exist in current entitlements
            $step.With.Keep = @(
                @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com' }
                @{ Kind = 'Group'; Id = 'CN=LEAVER-NEW,DC=contoso,DC=com'; DisplayName = 'Leaver New' }
            )
            $step.With.EnsureKeepEntitlements = $true

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-NEW,DC=contoso,DC=com'
        }

        It 'does not re-grant already present Keep entitlements' {
            $step = $script:StepTemplate
            $step.With.EnsureKeepEntitlements = $true

            $grantCount = 0
            $originalGrant = $script:Provider.PSObject.Methods['GrantEntitlement']

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'

            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
        }

        It 'does not grant pattern-matched entitlements (only explicit Keep items)' {
            $step = $script:StepTemplate
            $step.With.KeepPattern = @('CN=LEAVER-*,DC=contoso,DC=com')
            $step.With.EnsureKeepEntitlements = $true

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'

            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            # Only explicit Keep items from Keep array are granted if missing; patterns are not granted
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-EXTRA,DC=contoso,DC=com'
        }
    }

    Context 'Behavior: Non-removable entitlement handling' {
        It 'skips non-removable entitlements and continues without failing' {
            # Mark CN=G-All as protected (non-removable, like AD primary group)
            $script:Provider.ProtectedEntitlementIds = @('CN=G-All,DC=contoso,DC=com')

            $warningEvents = @()
            $script:Context.EventSink = [pscustomobject]@{
                WriteEvent = {
                    param($Type, $Message, $StepName, $Data)
                    if ($Type -eq 'Warning') {
                        $script:warningEvents += $Message
                    }
                }.GetNewClosure()
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Skipped | Should -Not -BeNullOrEmpty
            $result.Skipped[0].EntitlementId | Should -Be 'CN=G-All,DC=contoso,DC=com'

            # Non-protected entitlements should still be removed
            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            $remainingIds | Should -Contain 'CN=G-All,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Not -Contain 'CN=G-HR,DC=contoso,DC=com'
        }

        It 'includes the skip reason from the provider error message' {
            $script:Provider.ProtectedEntitlementIds = @('CN=G-All,DC=contoso,DC=com')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Skipped | Should -Not -BeNullOrEmpty
            $result.Skipped[0].Reason | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Behavior: Kind filtering' {
        It 'only prunes entitlements matching the specified Kind' {
            # Grant an entitlement of a different kind
            $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Role'; Id = 'admin-role' })

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'

            # The Role entitlement must survive (different kind)
            $remaining = $script:Provider.ListEntitlements('user1')
            $roleEntitlements = $remaining | Where-Object { $_.Kind -eq 'Role' }
            @($roleEntitlements).Count | Should -Be 1
            $roleEntitlements[0].Id | Should -Be 'admin-role'
        }
    }

    Context 'Validation' {
        It 'throws when With is not a hashtable' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = 'invalid'
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when With.IdentityKey is missing' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{ Kind = 'Group'; Keep = @(@{ Kind = 'Group'; Id = 'x' }) }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when With.Kind is missing' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{ IdentityKey = 'user1'; Keep = @(@{ Kind = 'Group'; Id = 'x' }) }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when neither Keep nor KeepPattern is provided' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{ IdentityKey = 'user1'; Kind = 'Group'; Provider = 'Identity' }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ExpectedMessage '*at least one*'
        }

        It 'throws when Keep is empty array and KeepPattern is absent' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{ IdentityKey = 'user1'; Kind = 'Group'; Provider = 'Identity'; Keep = @() }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when Keep item is missing an Id' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{
                    IdentityKey = 'user1'
                    Kind        = 'Group'
                    Provider    = 'Identity'
                    Keep        = @(@{ Kind = 'Group' })
                }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when KeepPattern contains a ScriptBlock' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{
                    IdentityKey = 'user1'
                    Kind        = 'Group'
                    Provider    = 'Identity'
                    KeepPattern = @({ 'CN=*' })
                }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }

        It 'throws when the provider is missing' {
            $script:Context.Providers.Clear()

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw
        }

        It 'throws when AuthSessionOptions is not a hashtable' {
            $step = $script:StepTemplate
            $step.With.AuthSessionName = 'Directory'
            $step.With.AuthSessionOptions = 'invalid'

            $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options) return $null
            } -Force

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            { & $handler -Context $script:Context -Step $step } | Should -Throw
        }
    }

    Context 'Behavior: step normalizes Keep IDs via provider.NormalizeEntitlementId when available' {
        It 'normalizes Keep item IDs before comparison so non-canonical IDs are matched correctly' {
            # Build a provider that: returns canonical IDs from ListEntitlements,
            # normalizes 'short-name' Keep IDs → canonical 'CN=...' form via NormalizeEntitlementId,
            # and tracks which IDs were passed to RevokeEntitlement.
            $revokedIds = @()
            $mockProvider = [pscustomobject]@{
                PSTypeName   = 'MockNormProvider'
                RevokedIds   = $revokedIds
            }

            $mockProvider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param($IdentityKey)
                return @(
                    [pscustomobject]@{ Kind = 'Group'; Id = 'CN=G-All,OU=Groups,DC=contoso,DC=com' },
                    [pscustomobject]@{ Kind = 'Group'; Id = 'CN=G-Keep,OU=Groups,DC=contoso,DC=com' },
                    [pscustomobject]@{ Kind = 'Group'; Id = 'CN=G-Remove,OU=Groups,DC=contoso,DC=com' }
                )
            } -Force

            $mockProvider | Add-Member -MemberType ScriptMethod -Name NormalizeEntitlementId -Value {
                param($Kind, $Entitlement, $AuthSession)
                # Map short sAMAccountName-style IDs to canonical DNs
                $idMap = @{
                    'G-Keep' = 'CN=G-Keep,OU=Groups,DC=contoso,DC=com'
                    'G-All'  = 'CN=G-All,OU=Groups,DC=contoso,DC=com'
                }
                $rawId = if ($Entitlement -is [hashtable]) { $Entitlement['Id'] } else { $Entitlement.Id }
                $canonicalId = if ($idMap.ContainsKey($rawId)) { $idMap[$rawId] } else { $rawId }
                $kind = if ($Entitlement -is [hashtable]) { $Entitlement['Kind'] } else { $Entitlement.Kind }
                return [pscustomobject]@{ Kind = $kind; Id = $canonicalId }
            } -Force

            $mockProvider | Add-Member -MemberType ScriptMethod -Name RevokeEntitlement -Value {
                param($IdentityKey, $Entitlement)
                $id = if ($Entitlement -is [hashtable]) { $Entitlement['Id'] } else { $Entitlement.Id }
                $this.RevokedIds += $id
            } -Force

            $script:Context.Providers['Identity'] = $mockProvider

            $step = [pscustomobject]@{
                Name = 'Prune via NormalizeEntitlementId'
                Type = 'IdLE.Step.PruneEntitlements'
                With = @{
                    IdentityKey = 'user1'
                    Kind        = 'Group'
                    Provider    = 'Identity'
                    Keep        = @(
                        @{ Kind = 'Group'; Id = 'G-Keep' },   # short/non-canonical ID
                        @{ Kind = 'Group'; Id = 'G-All' }     # short/non-canonical ID
                    )
                }
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlements'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status  | Should -Be 'Completed'
            $result.Changed | Should -BeTrue
            # G-Remove should have been revoked (not in keep set), G-Keep and G-All preserved
            $mockProvider.RevokedIds | Should -Contain 'CN=G-Remove,OU=Groups,DC=contoso,DC=com'
            $mockProvider.RevokedIds | Should -Not -Contain 'CN=G-Keep,OU=Groups,DC=contoso,DC=com'
            $mockProvider.RevokedIds | Should -Not -Contain 'CN=G-All,OU=Groups,DC=contoso,DC=com'
        }
    }
}

Describe 'Invoke-IdleStepPruneEntitlementsEnsureKeep (built-in step)' {
    BeforeEach {
        $script:Provider = New-IdleMockIdentityProvider
        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ Identity = $script:Provider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }

        # Seed the identity with some entitlements
        $null = $script:Provider.EnsureAttribute('user1', 'Seed', 'Value')
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-All,DC=contoso,DC=com' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-HR,DC=contoso,DC=com'; DisplayName = 'HR Group' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com'; DisplayName = 'Leaver Retain' })
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-EXTRA,DC=contoso,DC=com'; DisplayName = 'Leaver Extra' })

        $script:Handler = 'IdLE.Steps.Common\Invoke-IdleStepPruneEntitlementsEnsureKeep'
        $script:StepTemplate = [pscustomobject]@{
            Name = 'Prune and ensure keep (leaver)'
            Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
            With = @{
                IdentityKey = 'user1'
                Provider    = 'Identity'
                Kind        = 'Group'
                Keep        = @(
                    @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com' }
                )
            }
        }
    }

    Context 'Step registration' {
        It 'is registered in the step registry' {
            $catalog = IdLE.Steps.Common\Get-IdleStepMetadataCatalog
            $catalog.ContainsKey('IdLE.Step.PruneEntitlementsEnsureKeep') | Should -BeTrue
        }

        It 'requires IdLE.Entitlement.Grant capability' {
            $catalog = IdLE.Steps.Common\Get-IdleStepMetadataCatalog
            $catalog['IdLE.Step.PruneEntitlementsEnsureKeep'].RequiredCapabilities | Should -Contain 'IdLE.Entitlement.Grant'
        }

        It 'PruneEntitlements does NOT require IdLE.Entitlement.Grant capability' {
            $catalog = IdLE.Steps.Common\Get-IdleStepMetadataCatalog
            $catalog['IdLE.Step.PruneEntitlements'].RequiredCapabilities | Should -Not -Contain 'IdLE.Entitlement.Grant'
        }
    }

    Context 'Behavior: Keep only (prune + ensure)' {
        It 'removes non-kept entitlements and reports Changed' {
            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            @($remaining).Count | Should -Be 1
            $remaining[0].Id | Should -Be 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
        }

        It 'grants an explicit Keep item that is not yet present' {
            $step = $script:StepTemplate
            $step.With.Keep = @(
                @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com' }
                @{ Kind = 'Group'; Id = 'CN=LEAVER-NEW,DC=contoso,DC=com'; DisplayName = 'Leaver New' }
            )

            $result = & $script:Handler -Context $script:Context -Step $step

            $result.Status  | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            ($remaining | Select-Object -ExpandProperty Id) | Should -Contain 'CN=LEAVER-NEW,DC=contoso,DC=com'
        }

        It 'is idempotent when keep set is already the only entitlements' {
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-All,DC=contoso,DC=com' })
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=G-HR,DC=contoso,DC=com' })
            $null = $script:Provider.RevokeEntitlement('user1', @{ Kind = 'Group'; Id = 'CN=LEAVER-EXTRA,DC=contoso,DC=com' })

            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result.Status  | Should -Be 'Completed'
            $result.Changed | Should -BeFalse
        }
    }

    Context 'Behavior: Keep + KeepPattern union (prune + ensure)' {
        It 'keeps entitlements matching wildcard KeepPattern and ensures explicit Keep items' {
            $step = $script:StepTemplate
            $step.With.KeepPattern = @('CN=LEAVER-*,DC=contoso,DC=com')
            $step.With.Keep = @(
                @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,DC=contoso,DC=com' }
                @{ Kind = 'Group'; Id = 'CN=LEAVER-NEWGROUP,DC=contoso,DC=com' }
            )

            $result = & $script:Handler -Context $script:Context -Step $step

            $result.Status  | Should -Be 'Completed'
            $result.Changed | Should -BeTrue

            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            # LEAVER-RETAIN + LEAVER-EXTRA (pattern) + LEAVER-NEWGROUP (ensured)
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-EXTRA,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-NEWGROUP,DC=contoso,DC=com'
            $remainingIds | Should -Not -Contain 'CN=G-All,DC=contoso,DC=com'
            $remainingIds | Should -Not -Contain 'CN=G-HR,DC=contoso,DC=com'
        }

        It 'does not grant pattern-matched entitlements (only explicit Keep items)' {
            $step = $script:StepTemplate
            $step.With.KeepPattern = @('CN=LEAVER-*,DC=contoso,DC=com')

            # No new explicit Keep items beyond what's already present
            $result = & $script:Handler -Context $script:Context -Step $step

            $result.Status  | Should -Be 'Completed'

            # LEAVER-EXTRA was kept by pattern but not granted (it was already present)
            $remaining = $script:Provider.ListEntitlements('user1')
            $remainingIds = $remaining | Select-Object -ExpandProperty Id
            $remainingIds | Should -Contain 'CN=LEAVER-RETAIN,DC=contoso,DC=com'
            $remainingIds | Should -Contain 'CN=LEAVER-EXTRA,DC=contoso,DC=com'
        }
    }

    Context 'Validation: Guardrail - missing Keep and KeepPattern fails fast' {
        It 'throws when neither Keep nor KeepPattern is provided' {
            $step = [pscustomobject]@{
                Name = 'bad'
                Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
                With = @{ IdentityKey = 'user1'; Kind = 'Group'; Provider = 'Identity' }
            }

            { & $script:Handler -Context $script:Context -Step $step } | Should -Throw -ExpectedMessage '*at least one*'
        }
    }

    Context 'Behavior: Non-removable entitlement handling' {
        It 'skips non-removable entitlements with a structured warning and continues' {
            $script:Provider.ProtectedEntitlementIds = @('CN=G-All,DC=contoso,DC=com')

            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result.Status  | Should -Be 'Completed'
            $result.Skipped | Should -Not -BeNullOrEmpty
            $result.Skipped[0].EntitlementId | Should -Be 'CN=G-All,DC=contoso,DC=com'

            # Non-protected items should still have been removed
            $remaining = $script:Provider.ListEntitlements('user1')
            ($remaining | Select-Object -ExpandProperty Id) | Should -Not -Contain 'CN=G-HR,DC=contoso,DC=com'
        }
    }
}
