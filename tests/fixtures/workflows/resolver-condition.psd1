@{
  Name           = 'Resolver Condition Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Views.Identity.Entitlements' }
    }
  )
}
