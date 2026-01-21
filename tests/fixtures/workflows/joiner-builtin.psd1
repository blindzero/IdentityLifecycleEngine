@{
  Name           = 'Joiner - Built-in Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
