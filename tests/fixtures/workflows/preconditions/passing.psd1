@{
  Name           = 'Passing Preconditions'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.PassingPrecondition'
      Precondition = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
        )
      }
    }
  )
}
