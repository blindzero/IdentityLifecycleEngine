@{
  Name           = 'Condition Skip OnFailureStep'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Primary'; Type = 'IdLE.Step.PrimarySkipTest' }
  )
  OnFailureSteps = @(
    @{
      Name      = 'SkippedOnFailure'
      Type      = 'IdLE.Step.OnFailureSkipTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
      With      = @{
        Value = '{{Request.Intent.MissingKey}}'
      }
    }
  )
}
