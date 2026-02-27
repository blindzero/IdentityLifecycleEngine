function Invoke-IdleStepPruneEntitlements {
    <#
    .SYNOPSIS
    Converges an identity's entitlements by removing all non-kept entitlements of a given kind.

    .DESCRIPTION
    This provider-agnostic step implements "remove all except" semantics for entitlements.
    It is intended for leaver and mover workflows where all entitlements of a given kind
    (e.g. group memberships) must be removed, except for an explicit keep-set and/or
    entitlements matching a wildcard keep pattern.

    This step is remove-only. Use IdLE.Step.PruneEntitlementsEnsureKeep when you also need
    to guarantee that explicit Keep entitlements are present after the prune.

    The host must supply a provider that:

    - Advertises the IdLE.Entitlement.Prune capability (explicit opt-in)
    - Implements ListEntitlements(identityKey)
    - Implements RevokeEntitlement(identityKey, entitlement)

    Provider/system non-removable entitlements (e.g., AD primary group / Domain Users) are
    handled safely: if a revoke operation fails, the step emits a structured warning event,
    skips the entitlement, and continues. The workflow is not failed for these items.

    Authentication:

    - If With.AuthSessionName is present, the step acquires an auth session via
      Context.AcquireAuthSession(Name, Options) and passes it to provider methods
      if the provider supports an AuthSession parameter.
    - With.AuthSessionOptions (optional, hashtable) is passed to the broker for
      session selection (e.g., @{ Role = 'Tier0' }).
    - ScriptBlocks in AuthSessionOptions are rejected (security boundary).

    ### With.* Parameters

    | Key                  | Required | Type         | Description |
    | -------------------- | -------- | ------------ | ----------- |
    | IdentityKey          | Yes      | string       | Unique identity reference (e.g. sAMAccountName, UPN, or objectId). |
    | Kind                 | Yes      | string       | Entitlement kind to prune (provider-defined, e.g. Group, Role, License). |
    | Keep                 | No       | array        | Explicit entitlement objects to retain. Each entry must have an Id property; Kind and DisplayName are optional. At least one of Keep or KeepPattern is required. |
    | KeepPattern          | No       | string array | Wildcard strings (PowerShell -like semantics). Entitlements whose Id matches any pattern are kept. No regex or ScriptBlocks. |
    | Provider             | No       | string       | Provider alias from Context.Providers (default: Identity). |
    | AuthSessionName      | No       | string       | Name of the auth session to acquire via Context.AcquireAuthSession. |
    | AuthSessionOptions   | No       | hashtable    | Options passed to AcquireAuthSession for session selection (e.g. role-scoped sessions). |

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable.

    .EXAMPLE
    # Leaver workflow: remove all group memberships, keeping an explicit group and pattern matches.
    # This is remove-only. Use IdLE.Step.PruneEntitlementsEnsureKeep to also grant missing Keep entries.
    @{
        Name      = 'Prune group memberships (leaver)'
        Type      = 'IdLE.Step.PruneEntitlements'
        Condition = @{ Equals = @{ Path = 'Request.Intent.PruneGroups'; Value = $true } }
        With      = @{
            IdentityKey     = '{{Request.Identity.SamAccountName}}'
            Provider        = 'Identity'
            Kind            = 'Group'
            Keep            = @(
                @{ Kind = 'Group'; Id = 'CN=All-Users,OU=Groups,DC=contoso,DC=com' }
            )
            KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
            AuthSessionName = 'Directory'
        }
    }

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step
    )

    $with = $Step.With
    if ($null -eq $with -or -not ($with -is [hashtable])) {
        throw "PruneEntitlements requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Kind')) {
        if (-not $with.ContainsKey($key)) {
            throw "PruneEntitlements requires With.$key."
        }
    }

    $identityKey = [string]$with.IdentityKey
    $kind = [string]$with.Kind

    if ([string]::IsNullOrWhiteSpace($identityKey)) {
        throw "PruneEntitlements requires With.IdentityKey to be non-empty."
    }
    if ([string]::IsNullOrWhiteSpace($kind)) {
        throw "PruneEntitlements requires With.Kind to be non-empty."
    }

    $providerAlias = if ($with.ContainsKey('Provider')) { [string]$with.Provider } else { 'Identity' }

    # Parse explicit Keep items
    $keepItems = @()
    if ($with.ContainsKey('Keep') -and $null -ne $with.Keep) {
        foreach ($item in @($with.Keep)) {
            if ($item -is [scriptblock]) {
                throw "PruneEntitlements: Keep entries must not contain ScriptBlocks."
            }
            $keepItems += ConvertTo-IdlePruneEntitlement -Value $item -DefaultKind $kind
        }
    }

    # Parse KeepPattern items (wildcard strings only)
    $keepPatterns = @()
    if ($with.ContainsKey('KeepPattern') -and $null -ne $with.KeepPattern) {
        foreach ($p in @($with.KeepPattern)) {
            if ($p -is [scriptblock]) {
                throw "PruneEntitlements: KeepPattern entries must be strings, not ScriptBlocks."
            }
            $pStr = [string]$p
            if ([string]::IsNullOrWhiteSpace($pStr)) {
                throw "PruneEntitlements: KeepPattern entries must not be empty."
            }
            $keepPatterns += $pStr
        }
    }

    # At least one keep rule required (safety guardrail)
    if ($keepItems.Count -eq 0 -and $keepPatterns.Count -eq 0) {
        throw "PruneEntitlements requires at least one of: With.Keep or With.KeepPattern. At least one keep rule must be specified to prevent accidental removal of all entitlements."
    }

    $ensureKeep = $false
    if ($with.ContainsKey('EnsureKeepEntitlements') -and $null -ne $with.EnsureKeepEntitlements) {
        $ensureKeep = [bool]$with.EnsureKeepEntitlements
    }

    # Validate Context and Providers
    if (-not ($Context.PSObject.Properties.Name -contains 'Providers')) {
        throw "Context does not contain a Providers hashtable."
    }
    if ($null -eq $Context.Providers -or -not ($Context.Providers -is [hashtable])) {
        throw "Context.Providers must be a hashtable."
    }
    if (-not $Context.Providers.ContainsKey($providerAlias)) {
        throw "Provider '$providerAlias' was not supplied by the host."
    }

    # Auth session acquisition (optional, data-only)
    $authSession = $null
    if ($with.ContainsKey('AuthSessionName')) {
        $sessionName = [string]$with.AuthSessionName
        $sessionOptions = if ($with.ContainsKey('AuthSessionOptions')) { $with.AuthSessionOptions } else { $null }

        if ($null -ne $sessionOptions -and -not ($sessionOptions -is [hashtable])) {
            throw "With.AuthSessionOptions must be a hashtable or null."
        }

        $authSession = $Context.AcquireAuthSession($sessionName, $sessionOptions)
    }

    $provider = $Context.Providers[$providerAlias]

    # Validate required provider methods (step is the single source of delta computation)
    $requiredMethods = @('ListEntitlements', 'RevokeEntitlement')
    if ($ensureKeep) {
        $requiredMethods += 'GrantEntitlement'
    }
    foreach ($m in $requiredMethods) {
        if (-not ($provider.PSObject.Methods.Name -contains $m)) {
            throw "Provider '$providerAlias' must implement method '$m' for PruneEntitlements."
        }
    }

    # Normalize Keep IDs to canonical form via provider.NormalizeEntitlementId (when available).
    # This ensures correct comparison with the canonical IDs returned by ListEntitlements.
    # Each provider handles its own ID-type detection (e.g., GUID/DN/sAMAccountName for AD;
    # objectId/displayName for Entra ID).
    if ($keepItems.Count -gt 0 -and $provider.PSObject.Methods.Name -contains 'ResolveEntitlement') {
        $resolveSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['ResolveEntitlement'] -ParameterName 'AuthSession'
        $keepItems = @($keepItems | ForEach-Object {
            if ($resolveSupportsAuthSession -and $null -ne $authSession) {
                $provider.ResolveEntitlement($kind, $_, $authSession)
            } else {
                $provider.ResolveEntitlement($kind, $_)
            }
        })
    }

    $listSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['ListEntitlements'] -ParameterName 'AuthSession'
    $revokeSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['RevokeEntitlement'] -ParameterName 'AuthSession'
    $grantSupportsAuthSession = if ($ensureKeep) {
        Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['GrantEntitlement'] -ParameterName 'AuthSession'
    } else { $false }

    # Detect bulk-capable provider methods (e.g. Entra ID uses Graph $batch for efficiency)
    $hasBulkRevoke = $null -ne $provider.PSObject.Methods['BulkRevokeEntitlements']
    $bulkRevokeSupportsAuthSession = if ($hasBulkRevoke) {
        Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['BulkRevokeEntitlements'] -ParameterName 'AuthSession'
    } else { $false }
    $hasBulkGrant = $ensureKeep -and ($null -ne $provider.PSObject.Methods['BulkGrantEntitlements'])
    $bulkGrantSupportsAuthSession = if ($hasBulkGrant) {
        Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['BulkGrantEntitlements'] -ParameterName 'AuthSession'
    } else { $false }

    # 1. List current entitlements, filter by Kind
    $allCurrent = if ($listSupportsAuthSession -and $null -ne $authSession) {
        @($provider.ListEntitlements($identityKey, $authSession))
    } else {
        @($provider.ListEntitlements($identityKey))
    }

    $current = @($allCurrent | Where-Object {
        $null -ne $_ -and
        ($_.PSObject.Properties.Name -contains 'Kind') -and
        [string]::Equals([string]$_.Kind, $kind, [System.StringComparison]::OrdinalIgnoreCase)
    })

    # 2. Compute keep-set and remove-set
    $toKeep = @()
    $toRemove = @()

    foreach ($ent in $current) {
        if (Test-IdlePruneEntitlementShouldKeep -Ent $ent -KeepItems $keepItems -KeepPatterns $keepPatterns) {
            $toKeep += $ent
        } else {
            $toRemove += $ent
        }
    }

    # Emit plan intent event
    if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
        $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
        $Context.EventSink.WriteEvent('Information', "PruneEntitlements: plan - keep=$(@($toKeep).Count), remove=$(@($toRemove).Count)", $Step.Name, @{
            Kind       = $kind
            KeepCount  = @($toKeep).Count
            PruneCount = @($toRemove).Count
        })
    }

    $changed = $false
    $skippedItems = @()

    # 3. Revoke each entitlement in remove-set
    if ($hasBulkRevoke -and $toRemove.Count -gt 0) {
        # Bulk path: provider batches operations and returns per-item results with distinct status
        $bulkResults = if ($bulkRevokeSupportsAuthSession -and $null -ne $authSession) {
            @($provider.BulkRevokeEntitlements($identityKey, $toRemove, $authSession))
        } else {
            @($provider.BulkRevokeEntitlements($identityKey, $toRemove))
        }

        foreach ($br in $bulkResults) {
            if ($br.Error) {
                $skippedItems += [pscustomobject]@{
                    EntitlementId = [string]$br.Entitlement.Id
                    Reason        = [string]$br.Error
                }
                if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                    $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                    $Context.EventSink.WriteEvent('Warning', "PruneEntitlements: skipped non-removable entitlement '$($br.Entitlement.Id)': $($br.Error)", $Step.Name, @{
                        Kind          = $kind
                        EntitlementId = [string]$br.Entitlement.Id
                        Reason        = [string]$br.Error
                    })
                }
            } else {
                if ($br.Changed) { $changed = $true }
                if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                    $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                    $Context.EventSink.WriteEvent('Information', "PruneEntitlements: revoked entitlement '$($br.Entitlement.Id)'", $Step.Name, @{
                        Kind          = $kind
                        EntitlementId = [string]$br.Entitlement.Id
                    })
                }
            }
        }
    } else {
        # Per-item path: each revoke is attempted independently
        foreach ($ent in $toRemove) {
            try {
                if ($revokeSupportsAuthSession -and $null -ne $authSession) {
                    $revokeResult = $provider.RevokeEntitlement($identityKey, $ent, $authSession)
                } else {
                    $revokeResult = $provider.RevokeEntitlement($identityKey, $ent)
                }
                if ($revokeResult -and $revokeResult.Changed) {
                    $changed = $true
                }

                if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                    $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                    $Context.EventSink.WriteEvent('Information', "PruneEntitlements: revoked entitlement '$($ent.Id)'", $Step.Name, @{
                        Kind          = $kind
                        EntitlementId = [string]$ent.Id
                    })
                }
            }
            catch {
                # Non-removable or permission-denied entitlement: skip with warning
                $reason = $_.Exception.Message
                $skippedItems += [pscustomobject]@{
                    EntitlementId = [string]$ent.Id
                    Reason        = $reason
                }

                if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                    $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                    $Context.EventSink.WriteEvent('Warning', "PruneEntitlements: skipped non-removable entitlement '$($ent.Id)': $reason", $Step.Name, @{
                        Kind          = $kind
                        EntitlementId = [string]$ent.Id
                        Reason        = $reason
                    })
                }
            }
        }
    }

    # 4. If EnsureKeepEntitlements: grant any explicit Keep items that are missing
    if ($ensureKeep -and $keepItems.Count -gt 0) {
        $toEnsure = @($keepItems | Where-Object { $k = $_
            @($current | Where-Object {
                [string]::Equals([string]$_.Id, [string]$k.Id, [System.StringComparison]::OrdinalIgnoreCase)
            }).Count -eq 0
        })

        if ($hasBulkGrant -and $toEnsure.Count -gt 0) {
            # Bulk grant path
            $bulkResults = if ($bulkGrantSupportsAuthSession -and $null -ne $authSession) {
                @($provider.BulkGrantEntitlements($identityKey, $toEnsure, $authSession))
            } else {
                @($provider.BulkGrantEntitlements($identityKey, $toEnsure))
            }

            foreach ($br in $bulkResults) {
                if ($br.Error) {
                    $skippedItems += [pscustomobject]@{
                        EntitlementId = [string]$br.Entitlement.Id
                        Reason        = [string]$br.Error
                    }
                    if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                        $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                        $Context.EventSink.WriteEvent('Warning', "PruneEntitlements: failed to grant keep entitlement '$($br.Entitlement.Id)': $($br.Error)", $Step.Name, @{
                            Kind          = $kind
                            EntitlementId = [string]$br.Entitlement.Id
                            Reason        = [string]$br.Error
                        })
                    }
                } else {
                    if ($br.Changed) { $changed = $true }
                    if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                        $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                        $Context.EventSink.WriteEvent('Information', "PruneEntitlements: granted keep entitlement '$($br.Entitlement.Id)'", $Step.Name, @{
                            Kind          = $kind
                            EntitlementId = [string]$br.Entitlement.Id
                        })
                    }
                }
            }
        } else {
            foreach ($k in $toEnsure) {
                if ($grantSupportsAuthSession -and $null -ne $authSession) {
                    $result = $provider.GrantEntitlement($identityKey, $k, $authSession)
                } else {
                    $result = $provider.GrantEntitlement($identityKey, $k)
                }

                if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Changed') {
                    if ($result.Changed) {
                        $changed = $true
                    }
                } else {
                    # Fall back to assuming a change occurred if the provider does not return a standard result object
                    $changed = $true
                }
                if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink -and
                    $Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                    $Context.EventSink.WriteEvent('Information', "PruneEntitlements: granted keep entitlement '$($k.Id)'", $Step.Name, @{
                        Kind          = $kind
                        EntitlementId = [string]$k.Id
                    })
                }
            }
        }
    }

    return [pscustomobject]@{
        PSTypeName   = 'IdLE.StepResult'
        Name         = [string]$Step.Name
        Type         = [string]$Step.Type
        Status       = 'Completed'
        Changed      = $changed
        Error        = $null
        Skipped      = $skippedItems
    }
}
