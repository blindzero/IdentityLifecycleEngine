@{
  Name           = 'Template Test - Context'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        ObjectId = '{{Request.Context.Identity.ObjectId}}'
      }
    }
  )
}
