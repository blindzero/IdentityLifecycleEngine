@{
  Name           = 'Blocked Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.BlockedPrecondition'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
      OnPreconditionFalse = 'Blocked'
    }
    @{
      Name = 'Step2'
      Type = 'IdLE.Step.SecondStep'
    }
  )
}
