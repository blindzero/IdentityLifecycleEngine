@{
  Name           = 'Resolver Non-Allow-Listed Capability Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.Grant'
      With       = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
