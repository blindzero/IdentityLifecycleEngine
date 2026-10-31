@{
  Name           = 'Template Test - Escaped Mixed'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ and template {{Request.Intent.Name}}'
      }
    }
  )
}
