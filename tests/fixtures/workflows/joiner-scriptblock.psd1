@{
  Name           = 'Joiner - ScriptBlock Test'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.Step.Test'
    }
  )
}
