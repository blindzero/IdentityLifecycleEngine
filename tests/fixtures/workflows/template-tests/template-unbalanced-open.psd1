@{
  Name           = 'Template Test - Unbalanced Open'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.Name'
      }
    }
  )
}
