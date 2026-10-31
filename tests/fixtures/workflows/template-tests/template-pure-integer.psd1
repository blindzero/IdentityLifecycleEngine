@{
  Name           = 'Template Test - Pure Integer'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        UserId = '{{Request.Intent.UserId}}'
      }
    }
  )
}
