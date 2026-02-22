@{
  Name           = 'Resolver Condition Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Identity.Entitlements' }
    }
  )
}
