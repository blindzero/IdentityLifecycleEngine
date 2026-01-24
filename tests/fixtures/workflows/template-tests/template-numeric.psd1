@{
  Name           = 'Template Test - Numeric'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'ID: {{Request.Input.UserId}}'
      }
    }
  )
}
