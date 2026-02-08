@{
  Name           = 'Template Test - Mixed Boolean (String Interpolation)'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Message = 'Account enabled: {{Request.Input.Enabled}}'
      }
    }
  )
}
