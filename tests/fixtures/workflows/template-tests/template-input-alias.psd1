@{
  Name           = 'Template Test - Input Alias'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name}}'
      }
    }
  )
}
