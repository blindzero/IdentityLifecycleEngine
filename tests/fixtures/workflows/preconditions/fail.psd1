@{
  Name           = 'Fail Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'Test.IdLE.Step.FailPrecondition'
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
      OnPreconditionFalse = 'Fail'
    }
    @{
      Name = 'Step2'
      Type = 'Test.IdLE.Step.SecondStep'
    }
  )
}
