@{
  Name           = 'Template Test - Backslash Before Template'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
      }
    }
  )
}
