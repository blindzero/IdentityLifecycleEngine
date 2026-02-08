@{
  Name           = 'Template Test - Pure DateTime'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        StartDate = '{{Request.Input.StartDate}}'
      }
    }
  )
}
