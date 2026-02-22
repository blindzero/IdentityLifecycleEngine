@{
  Name           = 'Resolver Context Type Conflict Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
