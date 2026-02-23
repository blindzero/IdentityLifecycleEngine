@{
  Name           = 'Invalid OnPreconditionFalse'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.InvalidOPF'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
      OnPreconditionFalse = 'Skip'
    }
  )
}
