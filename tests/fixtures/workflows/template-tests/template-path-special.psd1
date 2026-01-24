@{
  Name           = 'Template Test - Path Special'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.User@Name}}'
      }
    }
  )
}
