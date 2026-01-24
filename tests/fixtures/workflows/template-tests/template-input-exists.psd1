@{
  Name           = 'Template Test - Input Exists'
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
