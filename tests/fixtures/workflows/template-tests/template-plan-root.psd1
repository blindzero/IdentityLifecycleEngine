@{
  Name           = 'Template Test - Plan Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Plan.WorkflowName}}'
      }
    }
  )
}
