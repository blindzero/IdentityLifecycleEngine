@{
  Name           = 'Template Test - Path Special'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.User@Name}}'
      }
    }
  )
}
