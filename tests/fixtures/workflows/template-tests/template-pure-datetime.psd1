@{
  Name           = 'Template Test - Pure DateTime'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        StartDate = '{{Request.Intent.StartDate}}'
      }
    }
  )
}
