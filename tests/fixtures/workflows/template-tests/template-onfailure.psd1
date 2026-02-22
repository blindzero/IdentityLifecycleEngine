@{
  Name           = 'Template Test - OnFailureSteps'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'MainStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Intent.Name}}'
      }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'FailureHandler'
      Type = 'IdLE.Step.Test'
      With = @{
        ErrorMessage = 'Failed for user {{Request.Intent.UserPrincipalName}}'
      }
    }
  )
}
