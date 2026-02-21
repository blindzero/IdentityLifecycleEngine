@{
  Name           = 'Template Test - Backslash Before Template'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
      }
    }
  )
}
