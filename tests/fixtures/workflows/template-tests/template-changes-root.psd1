@{
  Name           = 'Template Test - Changes Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Changes.Department}}'
      }
    }
  )
}
