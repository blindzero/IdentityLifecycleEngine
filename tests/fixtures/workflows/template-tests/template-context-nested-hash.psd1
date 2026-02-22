@{
  Name           = 'Template Test - Context Nested Hash'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Identity = @{
          Name  = '{{Request.Context.Identity.DisplayName}}'
          Email = '{{Request.Context.Identity.Mail}}'
        }
      }
    }
  )
}
