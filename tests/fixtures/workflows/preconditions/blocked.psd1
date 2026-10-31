@{
  Name           = 'Blocked Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'Test.IdLE.Step.BlockedPrecondition'
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
      OnPreconditionFalse = 'Blocked'
    }
    @{
      Name = 'Step2'
      Type = 'Test.IdLE.Step.SecondStep'
    }
  )
}
