# StepMetadataCatalog.psd1 - IdLE.Steps.Common
#
# Data-only metadata catalog for all common built-in IdLE step types.
# This file is loaded by the engine (manifest PrivateData.IdLE.StepCatalog) and by Get-IdleStepMetadataCatalog.
# It must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   Handler              - handler function exported by this module (bound to this module by the engine)
#   RequiredCapabilities - capability identifiers the step requires from providers
#   WithSchema           - declares the With key contract for plan-time validation:
#     RequiredKeys         - keys that MUST be present in With
#     OptionalKeys         - keys that MAY be present in With
#
@{
    # IdLE.Step.EmitEvent - writes a structured event to the event sink; no provider capabilities required.
    # Provider/AuthSessionName/AuthSessionOptions are accepted as optional routing hints:
    # the execution engine reads these from any step's With to resolve Request.Context.Current.*.
    'IdLE.Step.EmitEvent'                   = @{
        Handler              = 'Invoke-IdleStepEmitEvent'
        RequiredCapabilities = @()
        WithSchema           = @{
            RequiredKeys = @()
            OptionalKeys = @('Message', 'Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.CreateIdentity - provisions a new identity via the identity provider
    'IdLE.Step.CreateIdentity'              = @{
        Handler              = 'Invoke-IdleStepCreateIdentity'
        RequiredCapabilities = @('IdLE.Identity.Create')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Attributes')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.DisableIdentity - disables an existing identity via the identity provider
    'IdLE.Step.DisableIdentity'             = @{
        Handler              = 'Invoke-IdleStepDisableIdentity'
        RequiredCapabilities = @('IdLE.Identity.Disable')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnableIdentity - re-enables a disabled identity via the identity provider
    'IdLE.Step.EnableIdentity'              = @{
        Handler              = 'Invoke-IdleStepEnableIdentity'
        RequiredCapabilities = @('IdLE.Identity.Enable')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.DeleteIdentity - permanently removes an identity via the identity provider
    'IdLE.Step.DeleteIdentity'              = @{
        Handler              = 'Invoke-IdleStepDeleteIdentity'
        RequiredCapabilities = @('IdLE.Identity.Delete')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.MoveIdentity - moves an identity to a target container/OU
    'IdLE.Step.MoveIdentity'                = @{
        Handler              = 'Invoke-IdleStepMoveIdentity'
        RequiredCapabilities = @('IdLE.Identity.Move')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'TargetContainer')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnsureAttributes - idempotently sets attributes on an identity
    'IdLE.Step.EnsureAttributes'            = @{
        Handler              = 'Invoke-IdleStepEnsureAttributes'
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Attributes')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.EnsureEntitlement - idempotently grants or revokes a single entitlement
    'IdLE.Step.EnsureEntitlement'           = @{
        Handler              = 'Invoke-IdleStepEnsureEntitlement'
        RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Entitlement', 'State')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.RevokeIdentitySessions - revokes all active sessions for an identity
    'IdLE.Step.RevokeIdentitySessions'      = @{
        Handler              = 'Invoke-IdleStepRevokeIdentitySessions'
        RequiredCapabilities = @('IdLE.Identity.RevokeSessions')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey')
            OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.PruneEntitlements - remove-only: removes entitlements not in Keep/KeepPattern
    # Requires explicit prune opt-in capability plus list/revoke
    'IdLE.Step.PruneEntitlements'           = @{
        Handler              = 'Invoke-IdleStepPruneEntitlements'
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Kind')
            OptionalKeys = @('Provider', 'Keep', 'KeepPattern', 'AuthSessionName', 'AuthSessionOptions')
        }
    }

    # IdLE.Step.PruneEntitlementsEnsureKeep - remove + ensure keep present: prune + grant-back
    # KeepPattern is NOT in OptionalKeys because patterns cannot be granted (they are filter-only).
    'IdLE.Step.PruneEntitlementsEnsureKeep' = @{
        Handler              = 'Invoke-IdleStepPruneEntitlementsEnsureKeep'
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke', 'IdLE.Entitlement.Grant')
        WithSchema           = @{
            RequiredKeys = @('IdentityKey', 'Kind')
            OptionalKeys = @('Provider', 'Keep', 'AuthSessionName', 'AuthSessionOptions')
        }
    }
}
