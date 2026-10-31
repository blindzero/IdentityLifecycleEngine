@{
  Name           = 'Template Test - Input Exists'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.Name}}'
      }
    }
  )
}
