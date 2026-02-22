@{
  # Joiner workflow demonstrating ContextResolvers to enrich Request.Context at planning time.
  #
  # ContextResolvers run BEFORE step conditions are evaluated. They use read-only provider
  # capabilities to fetch data and write it under Request.Context.*.
  #
  # This example uses IdLE.Entitlement.List to pre-fetch the identity's current entitlements.
  # Steps can then reference Request.Context.Identity.Entitlements in their Condition.

  Name           = 'Joiner - ContextResolvers Demo'
  LifecycleEvent = 'Joiner'

  # Planning-time resolvers: run before condition evaluation, write to Request.Context.*
  ContextResolvers = @(
    @{
      # Fetch current entitlements for the identity being onboarded.
      Capability = 'IdLE.Entitlement.List'

      # The provider alias that supports IdLE.Entitlement.List.
      # If omitted, the first provider advertising the capability is used.
      Provider   = 'Identity'

      # Resolver inputs - use the identity key for this workflow.
      # In real workflows, use template placeholders like '{{Request.IdentityKeys.EmployeeId}}'.
      With       = @{
        IdentityKey = 'user1'
      }

      # Write resolved entitlements to Request.Context.Identity.Entitlements.
      # 'To' must always start with 'Context.' (writes restricted to Request.Context.*).
      To         = 'Context.Identity.Entitlements'
    }
  )

  Steps = @(
    @{
      # Always runs - ensures the base group membership.
      Name = 'EnsureBaseGroup'
      Type = 'IdLE.Step.EnsureEntitlement'
      With = @{
        IdentityKey  = 'user1'
        Entitlement  = @{ Kind = 'Group'; Id = 'all-employees'; DisplayName = 'All Employees' }
        State        = 'Present'
        Provider     = 'Identity'
      }
    }

    @{
      # Only grant the IT team group if the identity does not already have it.
      # This uses the pre-resolved entitlements from Request.Context.Identity.Entitlements.
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
