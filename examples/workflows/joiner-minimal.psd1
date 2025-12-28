@{
  Name           = 'Joiner - Minimal Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'EmitHello'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Hello from Joiner minimal workflow.'
      }
    }
  )
}
