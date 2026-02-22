@{
  Name           = 'Resolver Missing Capability Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      With = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
