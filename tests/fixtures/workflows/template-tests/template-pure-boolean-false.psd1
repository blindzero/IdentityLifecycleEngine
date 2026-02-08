@{
  Name           = 'Template Test - Pure Boolean False'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Enabled = '{{Request.Input.Enabled}}'
      }
    }
  )
}
