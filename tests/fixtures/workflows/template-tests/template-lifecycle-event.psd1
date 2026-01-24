@{
  Name           = 'Template Test - LifecycleEvent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Event = '{{Request.LifecycleEvent}}'
      }
    }
  )
}
