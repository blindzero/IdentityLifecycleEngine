@{
  Name           = 'Joiner - WithSchema Case Insensitive Keys'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'DisableStep'
      Type = 'IdLE.Step.DisableIdentity'
      With = @{ identitykey = 'user1' }
    }
  )
}
