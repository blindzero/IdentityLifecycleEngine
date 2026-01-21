@{
  Name           = 'Joiner - OnFailure Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Primary step'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Primary' }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'Containment'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
