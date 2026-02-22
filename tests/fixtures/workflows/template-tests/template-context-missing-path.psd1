@{
  Name           = 'Template Test - Context Missing Path'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Context.NonExistent}}'
      }
    }
  )
}
