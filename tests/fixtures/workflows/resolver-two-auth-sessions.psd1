@{
  Name           = 'Resolver Two Auth Sessions Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey     = 'user1'
        Provider        = 'Identity'
        AuthSessionName = 'Corp'
      }
    }
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey     = 'user1'
        Provider        = 'Identity'
        AuthSessionName = 'Tier0'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
