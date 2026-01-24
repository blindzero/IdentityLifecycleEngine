@{
  Name           = 'Template Test - Unbalanced Open'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name'
      }
    }
  )
}
