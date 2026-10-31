@{
  Name           = 'Template Test - Boolean'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = 'Enabled: {{Request.Intent.IsEnabled}}'
      }
    }
  )
}
