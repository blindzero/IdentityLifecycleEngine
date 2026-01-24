@{
  Name           = 'Template Test - Null Value'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.NullField}}'
      }
    }
  )
}
