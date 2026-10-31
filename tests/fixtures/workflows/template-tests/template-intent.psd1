@{
  Name           = 'Template Test - Intent'
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
