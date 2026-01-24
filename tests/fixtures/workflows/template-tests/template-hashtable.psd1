@{
  Name           = 'Template Test - Hashtable'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.UserData}}'
      }
    }
  )
}
