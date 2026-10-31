@{
  Name           = 'Continue Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'Test.IdLE.Step.ContinuePrecondition'
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
      OnPreconditionFalse = 'Continue'
    }
    @{
      Name = 'Step2'
      Type = 'Test.IdLE.Step.SecondStep'
    }
  )
}
