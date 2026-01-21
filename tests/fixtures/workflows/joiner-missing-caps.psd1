@{
  Name           = 'Joiner - Missing Capabilities'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
