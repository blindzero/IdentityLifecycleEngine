@{
  Name           = 'Template Test - Array'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Emails = @(
          '{{Request.Input.PrimaryEmail}}'
          '{{Request.Input.SecondaryEmail}}'
        )
      }
    }
  )
}
