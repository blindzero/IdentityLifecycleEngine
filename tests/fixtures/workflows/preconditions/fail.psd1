@{
  Name           = 'Fail Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.FailPrecondition'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
      OnPreconditionFalse = 'Fail'
    }
    @{
      Name = 'Step2'
      Type = 'IdLE.Step.SecondStep'
    }
  )
}
