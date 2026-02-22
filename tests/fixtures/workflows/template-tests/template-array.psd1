@{
  Name           = 'Template Test - Array'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Emails = @(
          '{{Request.Intent.PrimaryEmail}}'
          '{{Request.Intent.SecondaryEmail}}'
        )
      }
    }
  )
}
