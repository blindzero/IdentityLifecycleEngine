@{
  Name           = 'Template Test - Mixed Boolean (String Interpolation)'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Message = 'Account enabled: {{Request.Intent.Enabled}}'
      }
    }
  )
}
