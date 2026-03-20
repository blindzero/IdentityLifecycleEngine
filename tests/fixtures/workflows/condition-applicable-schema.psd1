@{
  Name           = 'Condition Applicable Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'StrictStep'
      Type      = 'IdLE.Step.StrictApplicableTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
    }
  )
}
