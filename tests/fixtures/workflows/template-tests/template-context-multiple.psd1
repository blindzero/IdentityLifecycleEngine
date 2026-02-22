@{
  Name           = 'Template Test - Context Multiple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Message = 'Identity {{Request.Context.Identity.DisplayName}} ({{Request.Context.Identity.ObjectId}}) loaded.'
      }
    }
  )
}
