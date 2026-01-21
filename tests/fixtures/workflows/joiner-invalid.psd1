@{
  Name           = 'Joiner - Invalid Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.Step.Test'
    }
  )
}
