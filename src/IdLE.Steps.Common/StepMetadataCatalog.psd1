# StepMetadataCatalog.psd1 - IdLE.Steps.Common
#
# Data-only metadata catalog for all common built-in IdLE step types.
# This file is loaded by the engine (manifest PrivateData.IdLE.StepCatalog) and by Get-IdleStepMetadataCatalog.
# It must remain data-only (no ScriptBlocks).
#
# Each entry maps a Step.Type to a metadata hashtable containing:
#   Handler              - handler function exported by this module (bound to this module by the engine)
#   RequiredCapabilities - capability identifiers the step requires from providers
#   Provider             - (optional) the step uses one provider: @{ DefaultAlias = '<alias>' }.
#                          The engine resolves it and adds the With keys Provider, AuthSessionName, AuthSessionOptions.
#   WithSchema           - typed With contract validated at plan time (see docs/extend/steps.md):
#     Keys                 - key name -> @{ Type; Required; Default; AllowedValues; AllowEmpty; Keys; Items; ... }
#
@{
    # IdLE.Step.EmitEvent - writes a structured event to the event sink; uses no provider.
    'IdLE.Step.EmitEvent'                   = @{
        Handler              = 'Invoke-IdleStepEmitEvent'
        RequiredCapabilities = @()
        WithSchema           = @{
            Keys = @{
                Message = @{ Type = 'String' }
                Type    = @{ Type = 'String' }
                Level   = @{ Type = 'String'; AllowedValues = @('Information', 'Warning', 'Error'); Default = 'Information' }
            }
        }
    }

    # IdLE.Step.CreateIdentity - provisions a new identity via the identity provider
    'IdLE.Step.CreateIdentity'              = @{
        Handler              = 'Invoke-IdleStepCreateIdentity'
        RequiredCapabilities = @('IdLE.Identity.Create')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Attributes  = @{ Type = 'Hashtable'; Required = $true }
            }
        }
    }

    # IdLE.Step.DisableIdentity - disables an existing identity via the identity provider
    'IdLE.Step.DisableIdentity'             = @{
        Handler              = 'Invoke-IdleStepDisableIdentity'
        RequiredCapabilities = @('IdLE.Identity.Disable')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.EnableIdentity - enables a disabled identity via the identity provider
    'IdLE.Step.EnableIdentity'              = @{
        Handler              = 'Invoke-IdleStepEnableIdentity'
        RequiredCapabilities = @('IdLE.Identity.Enable')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.DeleteIdentity - deletes an identity via the identity provider
    'IdLE.Step.DeleteIdentity'              = @{
        Handler              = 'Invoke-IdleStepDeleteIdentity'
        RequiredCapabilities = @('IdLE.Identity.Delete')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.MoveIdentity - moves an identity to a different container/OU
    'IdLE.Step.MoveIdentity'                = @{
        Handler              = 'Invoke-IdleStepMoveIdentity'
        RequiredCapabilities = @('IdLE.Identity.Move')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey     = @{ Type = 'String'; Required = $true }
                TargetContainer = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.EnsureAttributes - ensures multiple identity attributes match desired values.
    # Attributes is free-form (attribute name -> value; $null clears an attribute).
    'IdLE.Step.EnsureAttributes'            = @{
        Handler              = 'Invoke-IdleStepEnsureAttributes'
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Attributes  = @{ Type = 'Hashtable'; Required = $true }
            }
        }
    }

    # IdLE.Step.EnsureEntitlement - ensures an entitlement assignment is present or absent
    'IdLE.Step.EnsureEntitlement'           = @{
        Handler              = 'Invoke-IdleStepEnsureEntitlement'
        RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Entitlement = @{
                    Type                = 'Hashtable'
                    Required            = $true
                    # Provider-specific entitlement properties are passed through.
                    AllowAdditionalKeys = $true
                    Keys                = @{
                        Kind        = @{ Type = 'String'; Required = $true }
                        Id          = @{ Type = 'String'; Required = $true }
                        DisplayName = @{ Type = 'String' }
                    }
                }
                State       = @{ Type = 'String'; AllowedValues = @('Present', 'Absent'); Default = 'Present' }
            }
        }
    }

    # IdLE.Step.RevokeIdentitySessions - revokes all active sign-in sessions for an identity
    'IdLE.Step.RevokeIdentitySessions'      = @{
        Handler              = 'Invoke-IdleStepRevokeIdentitySessions'
        RequiredCapabilities = @('IdLE.Identity.RevokeSessions')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
            }
        }
    }

    # IdLE.Step.PruneEntitlements - remove-only: removes entitlements not in Keep/KeepPattern
    # Requires explicit prune opt-in capability plus list/revoke
    'IdLE.Step.PruneEntitlements'           = @{
        Handler              = 'Invoke-IdleStepPruneEntitlements'
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Kind        = @{ Type = 'String'; Required = $true }
                Keep        = @{
                    Type       = 'Array'
                    AllowEmpty = $true
                    Items      = @{
                        Type                = 'Hashtable'
                        AllowAdditionalKeys = $true
                        Keys                = @{
                            Kind        = @{ Type = 'String' }
                            Id          = @{ Type = 'String'; Required = $true }
                            DisplayName = @{ Type = 'String' }
                        }
                    }
                }
                KeepPattern = @{ Type = 'Array'; AllowEmpty = $true; Items = @{ Type = 'String' } }
            }
        }
    }

    # IdLE.Step.PruneEntitlementsEnsureKeep - remove + ensure keep present: prune + grant-back
    # KeepPattern is not supported because patterns cannot be granted (they are filter-only).
    'IdLE.Step.PruneEntitlementsEnsureKeep' = @{
        Handler              = 'Invoke-IdleStepPruneEntitlementsEnsureKeep'
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke', 'IdLE.Entitlement.Grant')
        Provider             = @{ DefaultAlias = 'Identity' }
        WithSchema           = @{
            Keys = @{
                IdentityKey = @{ Type = 'String'; Required = $true }
                Kind        = @{ Type = 'String'; Required = $true }
                Keep        = @{
                    Type       = 'Array'
                    AllowEmpty = $true
                    Items      = @{
                        Type                = 'Hashtable'
                        AllowAdditionalKeys = $true
                        Keys                = @{
                            Kind        = @{ Type = 'String' }
                            Id          = @{ Type = 'String'; Required = $true }
                            DisplayName = @{ Type = 'String' }
                        }
                    }
                }
            }
        }
    }
}
