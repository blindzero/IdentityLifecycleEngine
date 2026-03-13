@{
  Name           = 'Current Alias Cleanup On Fail'
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
      Name                = 'CurrentFailStep'
      Type                = 'IdLE.Step.CurrentCleanupTest'
      With                = @{ Provider = 'Identity' }
      # Precondition always fails: LifecycleEvent is Joiner, not Leaver.
      Precondition        = @{
        Equals = @{
          Path  = 'Plan.LifecycleEvent'
          Value = 'Leaver'
        }
      }
      OnPreconditionFalse = 'Fail'
    }
  )
}
