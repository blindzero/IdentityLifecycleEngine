@{
  Name           = 'Resolver Identity Read Two Auth Sessions Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      With       = @{
        IdentityKey     = 'user1'
        Provider        = 'Identity'
        AuthSessionName = 'Corp'
      }
    }
    @{
      Capability = 'IdLE.Identity.Read'
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
