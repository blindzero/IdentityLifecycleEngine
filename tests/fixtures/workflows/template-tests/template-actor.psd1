@{
  Name           = 'Template Test - Actor'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        ActorName = '{{Request.Actor}}'
      }
    }
  )
}
