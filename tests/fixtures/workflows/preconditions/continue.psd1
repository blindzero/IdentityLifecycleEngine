@{
  Name           = 'Continue Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.ContinuePrecondition'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
      OnPreconditionFalse = 'Continue'
    }
    @{
      Name = 'Step2'
      Type = 'IdLE.Step.SecondStep'
    }
  )
}
