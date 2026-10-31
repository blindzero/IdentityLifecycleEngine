@{
  Name           = 'Template Test - Providers Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Providers.AuthSessionBroker}}'
      }
    }
  )
}
