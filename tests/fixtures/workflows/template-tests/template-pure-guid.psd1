@{
  Name           = 'Template Test - Pure Guid'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        ObjectId = '{{Request.Intent.ObjectId}}'
      }
    }
  )
}
