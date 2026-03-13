@{
  Name           = 'Resolver Identity Read Two Providers Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Entra'
      }
    }
    @{
      Capability = 'IdLE.Identity.Read'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'HR'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
