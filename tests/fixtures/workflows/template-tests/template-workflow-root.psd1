@{
  Name           = 'Template Test - Workflow Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Workflow.Name}}'
      }
    }
  )
}
