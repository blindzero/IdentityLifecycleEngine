@{
  Name           = 'Template Test - Multiple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Message = 'User {{Request.Input.DisplayName}} ({{Request.Input.UserPrincipalName}}) is joining.'
      }
    }
  )
}
