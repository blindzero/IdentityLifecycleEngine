@{
  Name           = 'Joiner - When Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'EmitOnlyForJoiner'
      Type = 'IdLE.Step.EmitEvent'
      When = @{
        Path   = 'Plan.LifecycleEvent'
        Equals = 'Joiner'
      }
      With = @{
        Message = 'This step runs only when Plan.LifecycleEvent == Joiner.'
      }
    }
    @{
      Name = 'SkipForJoiner'
      Type = 'IdLE.Step.EmitEvent'
      When = @{
        Path   = 'Plan.LifecycleEvent'
        Equals = 'Leaver'
      }
      With = @{
        Message = 'You should never see this in a Joiner run.'
      }
    }
  )
}
