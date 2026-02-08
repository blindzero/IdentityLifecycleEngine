@{
  Name           = 'Template Test - Pure Boolean True'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        IsActive = '{{Request.Input.IsActive}}'
      }
    }
  )
}
