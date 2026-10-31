@{
  Name           = 'Template Test - Context Multiple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Message = 'Identity {{Request.Context.Identity.DisplayName}} ({{Request.Context.Identity.ObjectId}}) loaded.'
      }
    }
  )
}
