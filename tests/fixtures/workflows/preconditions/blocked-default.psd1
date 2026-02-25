@{
  Name           = 'Blocked Default'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.BlockedDefault'
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
