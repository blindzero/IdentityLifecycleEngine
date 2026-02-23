@{
  Name           = 'Fail Runs OnFailure'
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
      Name = 'Cleanup'
      Type = 'IdLE.Step.OnFailureCleanup'
    }
  )
}
