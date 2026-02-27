@{
  Name           = 'Resolver Context Type Conflict Test'
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
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
