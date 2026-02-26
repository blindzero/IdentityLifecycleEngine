@{
  Name           = 'Invalid OnPreconditionFalse'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.InvalidOPF'
      Precondition        = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
        )
      }
      OnPreconditionFalse = 'Skip'
    }
  )
}
