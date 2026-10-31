@{
  Name           = 'Template Test - Hashtable'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.UserData}}'
      }
    }
  )
}
