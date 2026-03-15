# StepMetadataCatalog.psd1 - IdLE.Steps.Common
#
# Data-only metadata catalog for all common built-in IdLE step types.
# This file is loaded by Get-IdleStepMetadataCatalog and must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   RequiredCapabilities - capability identifiers the step requires from providers
#   WithSchema           - declares the With key contract for plan-time validation:
#     RequiredKeys         - keys that MUST be present in With
#     OptionalKeys         - keys that MAY be present in With
#
@{
    # IdLE.Step.EmitEvent - writes a structured event to the event sink; no provider capabilities required
    'IdLE.Step.EmitEvent'                   = @{
        RequiredCapabilities = @()
        WithSchema           = @{
            RequiredKeys = @()
            OptionalKeys = @('Message')
        }
    }

    # IdLE.Step.CreateIdentity - provisions a new identity via the identity provider
    'IdLE.Step.CreateIdentity'              = @{
        RequiredCapabilities = @('IdLE.Identity.Create')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Attributes')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.DisableIdentity - disables an existing identity via the identity provider
    'IdLE.Step.DisableIdentity'             = @{
        RequiredCapabilities = @('IdLE.Identity.Disable')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnableIdentity - re-enables a disabled identity via the identity provider
    'IdLE.Step.EnableIdentity'              = @{
        RequiredCapabilities = @('IdLE.Identity.Enable')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.DeleteIdentity - permanently removes an identity via the identity provider
    'IdLE.Step.DeleteIdentity'              = @{
        RequiredCapabilities = @('IdLE.Identity.Delete')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.MoveIdentity - moves an identity to a target container/OU
    'IdLE.Step.MoveIdentity'                = @{
        RequiredCapabilities = @('IdLE.Identity.Move')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'TargetContainer')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnsureAttributes - idempotently sets attributes on an identity
    'IdLE.Step.EnsureAttributes'            = @{
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Attributes')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnsureEntitlement - idempotently grants or revokes a single entitlement
    'IdLE.Step.EnsureEntitlement'           = @{
        RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Entitlement', 'State')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.RevokeIdentitySessions - revokes all active sessions for an identity
    'IdLE.Step.RevokeIdentitySessions'      = @{
        RequiredCapabilities = @('IdLE.Identity.RevokeSessions')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.PruneEntitlements - remove-only: removes entitlements not in Keep/KeepPattern
    # Requires explicit prune opt-in capability plus list/revoke
    'IdLE.Step.PruneEntitlements'           = @{
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Kind')
            OptionalKeys = @('Provider', 'Keep', 'KeepPattern', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.PruneEntitlementsEnsureKeep - remove + ensure keep present: prune + grant-back
    # KeepPattern is NOT in OptionalKeys because patterns cannot be granted (they are filter-only).
    'IdLE.Step.PruneEntitlementsEnsureKeep' = @{
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke', 'IdLE.Entitlement.Grant')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Kind')
            OptionalKeys = @('Provider', 'Keep', 'AuthSessionName', 'AuthSessionOptions')
        }
    }
}
