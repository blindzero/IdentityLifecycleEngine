@{
  Name           = 'Resolver With To Key Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
