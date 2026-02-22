@{
  Name           = 'Resolver Empty Entitlements Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user2' }
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
