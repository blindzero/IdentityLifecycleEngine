@{
  Name           = 'Template Test - DesiredState'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Department = '{{Request.DesiredState.Department}}'
      }
    }
  )
}
