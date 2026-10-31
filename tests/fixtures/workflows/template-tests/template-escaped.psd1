@{
  Name           = 'Template Test - Escaped'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ braces here'
      }
    }
  )
}
