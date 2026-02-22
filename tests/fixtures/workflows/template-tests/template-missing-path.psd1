@{
  Name           = 'Template Test - Missing Path'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.NonExistent}}'
      }
    }
  )
}
