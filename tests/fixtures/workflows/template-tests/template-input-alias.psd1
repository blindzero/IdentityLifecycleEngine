@{
  Name           = 'Template Test - Input Alias'
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
