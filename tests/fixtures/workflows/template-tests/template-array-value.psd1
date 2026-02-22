@{
  Name           = 'Template Test - Array Value'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.Tags}}'
      }
    }
  )
}
