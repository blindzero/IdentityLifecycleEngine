@{
  Name           = 'Template Test - Path Spaces'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.User Name}}'
      }
    }
  )
}
