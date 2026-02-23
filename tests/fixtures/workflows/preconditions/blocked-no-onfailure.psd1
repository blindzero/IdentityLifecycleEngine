@{
  Name           = 'Blocked No OnFailure'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.BlockedNoOnFailure'
      Preconditions = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'Cleanup'
      Type = 'IdLE.Step.OnFailureCleanup'
    }
  )
}
