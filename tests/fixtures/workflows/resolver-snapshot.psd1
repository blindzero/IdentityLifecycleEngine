@{
  Name           = 'Resolver Snapshot Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'snap-user'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
