@{
  Name           = 'Template Test - Unbalanced Close'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = 'Request.Intent.Name}}'
      }
    }
  )
}
