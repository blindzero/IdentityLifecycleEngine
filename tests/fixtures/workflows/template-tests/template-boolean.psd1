@{
  Name           = 'Template Test - Boolean'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Enabled: {{Request.Input.IsEnabled}}'
      }
    }
  )
}
