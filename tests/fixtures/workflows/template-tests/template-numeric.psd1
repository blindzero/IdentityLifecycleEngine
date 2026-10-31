@{
  Name           = 'Template Test - Numeric'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = 'ID: {{Request.Intent.UserId}}'
      }
    }
  )
}
