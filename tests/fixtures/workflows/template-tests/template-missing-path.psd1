@{
  Name           = 'Template Test - Missing Path'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.NonExistent}}'
      }
    }
  )
}
