@{
  Name           = 'Resolver Identity Read Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Identity.Profile' }
    }
  )
}
