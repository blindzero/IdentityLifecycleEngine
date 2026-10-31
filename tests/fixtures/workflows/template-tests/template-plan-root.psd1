@{
  Name           = 'Template Test - Plan Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Plan.WorkflowName}}'
      }
    }
  )
}
