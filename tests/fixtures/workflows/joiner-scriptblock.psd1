@{
  Name           = 'Joiner - ScriptBlock Test'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.IdLE.Step.Test'
    }
  )
}
