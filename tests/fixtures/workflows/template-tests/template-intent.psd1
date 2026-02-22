@{
  Name           = 'Template Test - Intent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Department = '{{Request.Intent.Department}}'
      }
    }
  )
}
