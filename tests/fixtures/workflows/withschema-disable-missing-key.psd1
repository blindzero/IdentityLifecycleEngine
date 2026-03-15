@{
  Name           = 'Joiner - WithSchema Missing Required Key'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'DisableStep'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
