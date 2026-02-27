@{
  Name           = 'Resolver Empty Entitlements Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'user2'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{
      Name      = 'NeedsEntitlements'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Identity.Entitlements' }
    }
  )
}
