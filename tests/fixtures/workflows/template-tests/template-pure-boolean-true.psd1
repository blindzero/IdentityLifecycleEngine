@{
  Name           = 'Template Test - Pure Boolean True'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        IsActive = '{{Request.Intent.IsActive}}'
      }
    }
  )
}
