@{
  Name           = 'Template Test - Actor'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        ActorName = '{{Request.Actor}}'
      }
    }
  )
}
