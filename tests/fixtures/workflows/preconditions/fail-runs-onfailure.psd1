@{
  Name           = 'Fail Runs OnFailure'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'Test.IdLE.Step.FailRunsOnFailure'
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
  )
  OnFailureSteps = @(
    @{
      Name = 'Cleanup'
      Type = 'Test.IdLE.Step.OnFailureCleanup'
    }
  )
}
