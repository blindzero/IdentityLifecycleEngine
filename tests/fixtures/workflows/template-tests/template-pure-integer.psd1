@{
  Name           = 'Template Test - Pure Integer'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        UserId = '{{Request.Input.UserId}}'
      }
    }
  )
}
