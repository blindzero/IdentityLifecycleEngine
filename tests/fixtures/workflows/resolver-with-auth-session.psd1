@{
  Name           = 'Resolver Auth Session Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{
        IdentityKey       = 'user1'
        AuthSessionName   = 'TestSession'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
