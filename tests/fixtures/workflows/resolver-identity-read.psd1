@{
  Name           = 'Resolver Identity Read Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Providers.Identity.Default.Identity.Profile' }
    }
  )
}
