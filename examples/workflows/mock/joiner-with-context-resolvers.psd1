@{
  # Joiner workflow demonstrating ContextResolvers to enrich Request.Context at planning time.
  #
  # ContextResolvers run BEFORE step conditions are evaluated. They use read-only provider
  # capabilities to fetch data and write it under Request.Context.*.
  #
  # Each capability writes to a predefined path (no user-configurable 'To'):
  #   IdLE.Entitlement.List -> Request.Context.Identity.Entitlements
  #   IdLE.Identity.Read    -> Request.Context.Identity.Profile

  Name           = 'Joiner - ContextResolvers Demo'
  LifecycleEvent = 'Joiner'

  # Planning-time resolvers: run before condition evaluation.
  # Each capability has a predefined output path under Request.Context.*
  ContextResolvers = @(
    @{
      # Fetch current entitlements for the identity being onboarded.
      # Writes to Request.Context.Identity.Entitlements (predefined).
      Capability = 'IdLE.Entitlement.List'

      # Resolver inputs.
      With       = @{
        IdentityKey = 'user1'
        # Provider alias that supports IdLE.Entitlement.List.
        # If omitted, the provider is auto-selected when exactly one match exists.
        Provider    = 'Identity'
      }
    }
  )

  Steps = @(
    @{
      # Always runs - ensures the base group membership.
      Name = 'EnsureBaseGroup'
      Type = 'IdLE.Step.EnsureEntitlement'
      With = @{
        IdentityKey = 'user1'
        Entitlement = @{ Kind = 'Group'; Id = 'all-employees' }
        State       = 'Present'
        Provider    = 'Identity'
      }
    }

    @{
      # Runs only when entitlements were successfully pre-resolved by the ContextResolver.
      # References the predefined context path for IdLE.Entitlement.List.
      Name = 'EmitContextAvailable'
      Type = 'IdLE.Step.EmitEvent'
      Condition = @{
        Exists = 'Request.Context.Identity.Entitlements'
      }
      With = @{
        Message = 'Entitlement context was pre-resolved by ContextResolvers and is available for planning.'
      }
    }
  )
}
