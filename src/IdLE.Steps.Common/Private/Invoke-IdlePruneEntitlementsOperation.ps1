function Invoke-IdlePruneEntitlementsOperation {
    # Shared implementation of IdLE.Step.PruneEntitlements and IdLE.Step.PruneEntitlementsEnsureKeep.
    # -EnsureKeep additionally grants explicit Keep entries that are missing.
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'Used by the nested Write-IdlePruneEvent function.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'StepName', Justification = 'Used by the nested Write-IdlePruneEvent function.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $StepName,

        [Parameter()]
        [switch] $EnsureKeep
    )

    function Write-IdlePruneEvent {
        param([string] $Type, [string] $Message, [hashtable] $Data, [string] $Level = 'Information')
        $Context.EventSink.WriteEvent($Type, $Message, $StepName, $Data, $Level)
    }

    $identityKey = [string]$With.IdentityKey
    $kind = [string]$With.Kind

    # Checked up front: the per-item revoke path below treats revoke failures as skipped entitlements,
    # which must not hide a provider that cannot revoke at all.
    $requiredMethods = @('ListEntitlements', 'RevokeEntitlement')
    if ($EnsureKeep) { $requiredMethods += 'GrantEntitlement' }
    foreach ($method in $requiredMethods) {
        if (-not $Provider.HasMethod($method)) {
            throw "Provider '$($Provider.Alias)' must implement method '$method' for PruneEntitlements."
        }
    }

    $keepItems = @()
    if ($With.ContainsKey('Keep')) {
        foreach ($item in @($With.Keep)) {
            $keepItems += ConvertTo-IdlePruneEntitlement -Value $item -Kind $kind
        }
    }

    $keepPatterns = if ($With.ContainsKey('KeepPattern')) { @($With.KeepPattern) } else { @() }

    # (No guardrail: empty keep-set is valid - prune everything of the given Kind)

    # Normalize Keep IDs to canonical form via ResolveEntitlement (when available) so that they compare
    # correctly with the canonical IDs returned by ListEntitlements. Each provider handles its own
    # ID-type detection (e.g., GUID/DN/sAMAccountName for AD; objectId/displayName for Entra ID).
    if ($keepItems.Count -gt 0 -and $Provider.HasMethod('ResolveEntitlement')) {
        $keepItems = @($keepItems | ForEach-Object { $Provider.Invoke('ResolveEntitlement', @($_)) })
    }

    # 1. List current entitlements, filter by Kind.
    # Pass Kind when supported so the provider can skip unrelated directory objects
    # (e.g. avoid AU Graph calls for Group-only prunes).
    $listArguments = if ($Provider.HasParameter('ListEntitlements', 'Kind')) { @($identityKey, $kind) } else { @($identityKey) }
    $allCurrent = @($Provider.Invoke('ListEntitlements', $listArguments))

    $current = @(
        $allCurrent | Where-Object { $null -ne $_ -and
            ($_.PSObject.Properties.Name -contains 'Kind') -and
            [string]::Equals([string]$_.Kind, $kind, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    # 2. Compute keep-set and remove-set
    $toKeep = @()
    $toRemove = @()

    foreach ($ent in $current) {
        if (Test-IdlePruneEntitlementShouldKeep -Ent $ent -KeepItems $keepItems -KeepPatterns $keepPatterns) {
            $toKeep += $ent
        }
        else {
            $toRemove += $ent
        }
    }

    Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.Planned' `
        -Message "PruneEntitlements: plan - keep=$(@($toKeep).Count), remove=$(@($toRemove).Count)" `
        -Data @{ Kind = $kind; KeepCount = @($toKeep).Count; PruneCount = @($toRemove).Count }

    $changed = $false
    $skippedItems = @()

    # 3. Revoke each entitlement in remove-set
    if ($Provider.HasMethod('BulkRevokeEntitlements') -and $toRemove.Count -gt 0) {
        # Bulk path: provider batches operations and returns per-item results with distinct status
        $bulkResults = @($Provider.Invoke('BulkRevokeEntitlements', @($identityKey, $toRemove)))

        foreach ($br in $bulkResults) {
            $entitlementId = [string]$br.Entitlement.Id
            if ($br.Error) {
                $skippedItems += [pscustomobject]@{ EntitlementId = $entitlementId; Reason = [string]$br.Error }
                Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.EntitlementSkipped' `
                    -Message "PruneEntitlements: skipped non-removable entitlement '$entitlementId': $($br.Error)" `
                    -Data @{ Kind = $kind; EntitlementId = $entitlementId; Reason = [string]$br.Error } -Level 'Warning'
            }
            else {
                if ($br.Changed) { $changed = $true }
                Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.EntitlementRevoked' `
                    -Message "PruneEntitlements: revoked entitlement '$entitlementId'" `
                    -Data @{ Kind = $kind; EntitlementId = $entitlementId }
            }
        }
    }
    else {
        # Per-item path: each revoke is attempted independently
        foreach ($ent in $toRemove) {
            $entitlementId = [string]$ent.Id
            try {
                $revokeResult = $Provider.Invoke('RevokeEntitlement', @($identityKey, $ent))
                if ($revokeResult -and $revokeResult.Changed) {
                    $changed = $true
                }

                Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.EntitlementRevoked' `
                    -Message "PruneEntitlements: revoked entitlement '$entitlementId'" `
                    -Data @{ Kind = $kind; EntitlementId = $entitlementId }
            }
            catch {
                # Non-removable or permission-denied entitlement: skip with warning
                $reason = $_.Exception.Message
                $skippedItems += [pscustomobject]@{ EntitlementId = $entitlementId; Reason = $reason }
                Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.EntitlementSkipped' `
                    -Message "PruneEntitlements: skipped non-removable entitlement '$entitlementId': $reason" `
                    -Data @{ Kind = $kind; EntitlementId = $entitlementId; Reason = $reason } -Level 'Warning'
            }
        }
    }

    # 4. EnsureKeep: grant any explicit Keep items that are missing
    if ($EnsureKeep -and $keepItems.Count -gt 0) {
        $toEnsure = @($keepItems | Where-Object { $k = $_
                @($current | Where-Object {
                        [string]::Equals([string]$_.Id, [string]$k.Id, [System.StringComparison]::OrdinalIgnoreCase)
                    }
                ).Count -eq 0
            }
        )

        if ($Provider.HasMethod('BulkGrantEntitlements') -and $toEnsure.Count -gt 0) {
            $bulkResults = @($Provider.Invoke('BulkGrantEntitlements', @($identityKey, $toEnsure)))

            foreach ($br in $bulkResults) {
                $entitlementId = [string]$br.Entitlement.Id
                if ($br.Error) {
                    $skippedItems += [pscustomobject]@{ EntitlementId = $entitlementId; Reason = [string]$br.Error }
                    Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.KeepGrantFailed' `
                        -Message "PruneEntitlements: failed to grant keep entitlement '$entitlementId': $($br.Error)" `
                        -Data @{ Kind = $kind; EntitlementId = $entitlementId; Reason = [string]$br.Error } -Level 'Warning'
                }
                else {
                    if ($br.Changed) { $changed = $true }
                    Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.KeepGranted' `
                        -Message "PruneEntitlements: granted keep entitlement '$entitlementId'" `
                        -Data @{ Kind = $kind; EntitlementId = $entitlementId }
                }
            }
        }
        else {
            foreach ($k in $toEnsure) {
                $result = $Provider.Invoke('GrantEntitlement', @($identityKey, $k))

                # Providers without a result object are assumed to have changed the assignment.
                if ($null -eq $result -or $result.PSObject.Properties.Name -notcontains 'Changed' -or $result.Changed) {
                    $changed = $true
                }

                Write-IdlePruneEvent -Type 'IdLE.Step.PruneEntitlements.KeepGranted' `
                    -Message "PruneEntitlements: granted keep entitlement '$($k.Id)'" `
                    -Data @{ Kind = $kind; EntitlementId = [string]$k.Id }
            }
        }
    }

    return @{
        Changed = $changed
        Data    = @{ Skipped = $skippedItems }
    }
}
