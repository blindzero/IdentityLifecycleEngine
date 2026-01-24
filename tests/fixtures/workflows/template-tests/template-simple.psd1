@{
  Name           = 'Template Test - Simple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        UserName = '{{Request.Input.UserPrincipalName}}'
      }
    }
  )
}
