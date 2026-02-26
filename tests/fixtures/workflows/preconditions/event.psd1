@{
  Name           = 'Precondition Event'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name              = 'Step1'
      Type              = 'IdLE.Step.PreconditionEvent'
      Precondition      = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
        )
      }
      PreconditionEvent = @{
        Type    = 'ManualActionRequired'
        Message = 'Perform Intune wipe before proceeding'
        Data    = @{
          Reason = 'BYOD wipe not confirmed'
        }
      }
    }
  )
}
