@{
  Name           = 'Template Test - Pure Boolean False'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Enabled = '{{Request.Intent.Enabled}}'
      }
    }
  )
}
