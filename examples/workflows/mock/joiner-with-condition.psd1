@{
  Name           = 'Joiner - Condition Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'EmitOnlyForJoiner'
      Type = 'IdLE.Step.EmitEvent'
      Condition = @{
        Equals = @{
          Path   = 'Plan.LifecycleEvent'
          Value  = 'Joiner'
        }
      }
      With = @{
        Message = 'This step runs only if Plan.LifecycleEvent == Joiner.'
      }
    }
    @{
      Name = 'SkipForJoiner'
      Type = 'IdLE.Step.EmitEvent'
      Condition = @{
        Equals = @{
          Path   = 'Plan.LifecycleEvent'
          Value = 'Leaver'
        }
      }
      With = @{
        Message = 'You should never see this in a Joiner run.'
      }
    }
  )
}
