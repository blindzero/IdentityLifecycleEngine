@{
  Name           = 'Joiner - Invalid Capability'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.IdLE.Step.Test'
    }
  )
}
