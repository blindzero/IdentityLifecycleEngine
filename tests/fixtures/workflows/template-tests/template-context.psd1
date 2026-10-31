@{
  Name           = 'Template Test - Context'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        ObjectId = '{{Request.Context.Identity.ObjectId}}'
      }
    }
  )
}
