@{
  Name           = 'Condition Exists Absent Path'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'ConditionalExistsStep'
      Type      = 'IdLE.Step.ExistsConditionTest'
      Condition = @{ Exists = 'Request.Context.Views.Identity.Profile.Attributes.Region' }
      With      = @{
        Value = '{{Request.Context.Views.Identity.Profile.Attributes.Region}}'
      }
    }
  )
}
