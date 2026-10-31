@{
  Name           = 'Blocked Default'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'Test.IdLE.Step.BlockedDefault'
      Precondition = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
        )
      }
    }
  )
}
