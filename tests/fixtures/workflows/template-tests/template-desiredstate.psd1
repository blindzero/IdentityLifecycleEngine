@{
  Name           = 'Template Test - DesiredState'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Department = '{{Request.Intent.Department}}'
      }
    }
  )
}
