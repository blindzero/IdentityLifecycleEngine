@{
  Name           = 'Template Test - LifecycleEvent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Event = '{{Request.LifecycleEvent}}'
      }
    }
  )
}
