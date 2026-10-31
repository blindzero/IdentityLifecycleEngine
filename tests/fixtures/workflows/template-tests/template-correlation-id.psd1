@{
  Name           = 'Template Test - CorrelationId'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Id = '{{Request.CorrelationId}}'
      }
    }
  )
}
