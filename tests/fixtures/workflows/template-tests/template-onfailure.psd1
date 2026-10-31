@{
  Name           = 'Template Test - OnFailureSteps'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'MainStep'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.Name}}'
      }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'FailureHandler'
      Type = 'Test.IdLE.Step.Test'
      With = @{
        ErrorMessage = 'Failed for user {{Request.Intent.UserPrincipalName}}'
      }
    }
  )
}
