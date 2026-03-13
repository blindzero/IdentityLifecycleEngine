@{
  Name           = 'Resolver Two Providers Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Entra'
      }
    }
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'AD'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
