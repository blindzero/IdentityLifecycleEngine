@{
  Name           = 'Template Test - Pure Guid'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        ObjectId = '{{Request.Input.ObjectId}}'
      }
    }
  )
}
