@{
  Name           = 'Template Test - Nested Hash'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        User = @{
          Name  = '{{Request.Intent.DisplayName}}'
          Email = '{{Request.Intent.Mail}}'
        }
      }
    }
  )
}
