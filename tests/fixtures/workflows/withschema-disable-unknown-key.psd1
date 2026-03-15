@{
  Name           = 'Joiner - WithSchema Unknown Key'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'DisableStep'
      Type = 'IdLE.Step.DisableIdentity'
      With = @{ IdentityKey = 'user1'; UnknownParam = 'bad' }
    }
  )
}
