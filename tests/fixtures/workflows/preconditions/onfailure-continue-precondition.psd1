@{
  Name           = 'Continue OnFailure Precondition'
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
      Name                = 'Cleanup'
      Type                = 'Test.IdLE.Step.OnFailureCleanup'
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
  )
}
