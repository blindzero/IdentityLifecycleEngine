@{
  Name           = 'Template Test - Multiple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Message = 'User {{Request.Intent.DisplayName}} ({{Request.Intent.UserPrincipalName}}) is joining.'
      }
    }
  )
}
