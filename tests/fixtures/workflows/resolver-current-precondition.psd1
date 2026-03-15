@{
  Name           = 'Resolver Current Precondition Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{
      Name         = 'CurrentPreconditionStep'
      Type         = 'IdLE.Step.CurrentTest'
      With         = @{
        Provider = 'Identity'
      }
      # Precondition uses Current alias: resolves to Providers.Identity.Default at execution time
      Precondition = @{ Exists = 'Request.Context.Current.Identity.Entitlements' }
    }
  )
}
