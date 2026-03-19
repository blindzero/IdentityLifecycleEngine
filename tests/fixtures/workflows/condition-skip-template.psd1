@{
  Name           = 'Condition Skip Template'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.ConditionalSkipTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
      With      = @{
        Value = '{{Request.Intent.MissingKey}}'
      }
    }
  )
}
