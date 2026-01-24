@{
  Name           = 'Template Test - CorrelationId'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Id = '{{Request.CorrelationId}}'
      }
    }
  )
}
