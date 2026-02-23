@{
  Name           = 'Continue OnFailure Precondition'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.FailRunsOnFailure'
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
  )
  OnFailureSteps = @(
    @{
      Name                = 'Cleanup'
      Type                = 'IdLE.Step.OnFailureCleanup'
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
  )
}
