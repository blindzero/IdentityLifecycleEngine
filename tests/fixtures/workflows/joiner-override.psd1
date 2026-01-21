@{
  Name           = 'Joiner - Override Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
