@{
  Name           = 'Template Test - Escaped Mixed'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ and template {{Request.Input.Name}}'
      }
    }
  )
}
