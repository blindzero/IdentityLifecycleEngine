@{
  Name           = 'Condition Skip OnFailureStep'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Primary'; Type = 'Test.IdLE.Step.PrimarySkipTest' }
  )
  OnFailureSteps = @(
    @{
      Name      = 'SkippedOnFailure'
      Type      = 'Test.IdLE.Step.OnFailureSkipTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
      With      = @{
        Value = '{{Request.Intent.MissingKey}}'
      }
    }
  )
}
