@{
  Name           = 'Template Test - Escaped Invalid Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '\{{Request.InvalidRoot}}'
      }
    }
  )
}
