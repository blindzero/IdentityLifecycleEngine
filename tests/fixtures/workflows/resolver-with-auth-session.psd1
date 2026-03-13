@{
  Name           = 'Resolver Auth Session Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey     = 'user1'
        Provider        = 'Identity'
        AuthSessionName = 'TestSession'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
