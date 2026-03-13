@{
  Name           = 'Resolver Invalid Auth Session Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey     = 'user1'
        Provider        = 'Identity'
        AuthSessionName = 'Invalid.Session.Name'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
