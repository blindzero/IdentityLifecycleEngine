@{
  Name           = 'Template Test - Providers Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Providers.AuthSessionBroker}}'
      }
    }
  )
}
