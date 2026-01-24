@{
  Name           = 'Template Test - Escaped'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ braces here'
      }
    }
  )
}
