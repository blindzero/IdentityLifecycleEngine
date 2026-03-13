@{
  # Joiner workflow demonstrating ContextResolvers to enrich Request.Context at planning time.
  #
  # ContextResolvers run BEFORE step conditions are evaluated. They use read-only provider
  # capabilities to fetch data and write it under provider/auth-scoped namespaces plus
  # engine-defined Views:
  #
  #   Source of truth (scoped): Request.Context.Providers.<Provider>.<AuthKey>.<CapabilitySubPath>
  #     e.g. IdLE.Entitlement.List -> Request.Context.Providers.Identity.Default.Identity.Entitlements
  #     e.g. IdLE.Identity.Read    -> Request.Context.Providers.Identity.Default.Identity.Profile
  #
  #   Global view (merged from all providers): Request.Context.Views.Identity.Entitlements
  #   Provider view (merged for one provider): Request.Context.Views.Providers.Identity.Identity.Entitlements

  Name           = 'Joiner - ContextResolvers Demo'
  LifecycleEvent = 'Joiner'

  # Planning-time resolvers: run before condition evaluation.
  # Each capability writes to a provider/auth-scoped path and updates deterministic Views.
  ContextResolvers = @(
    @{
      # Fetch current entitlements for the identity being onboarded.
      # Source of truth: Request.Context.Providers.Identity.Default.Identity.Entitlements
      # Global view:     Request.Context.Views.Identity.Entitlements
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
      # Uses the global View path (all providers merged), which is the most common reference pattern.
      Name = 'EmitContextAvailable'
      Type = 'IdLE.Step.EmitEvent'
      Condition = @{
        Exists = 'Request.Context.Views.Identity.Entitlements'
      }
      With = @{
        Message = 'Entitlement context was pre-resolved by ContextResolvers and is available for planning.'
      }
    }
  )
}
