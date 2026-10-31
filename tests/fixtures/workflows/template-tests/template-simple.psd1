@{
  Name           = 'Template Test - Simple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        UserName = '{{Request.Intent.UserPrincipalName}}'
      }
    }
  )
}
