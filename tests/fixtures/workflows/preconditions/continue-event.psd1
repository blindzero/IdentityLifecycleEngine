@{
  Name           = 'Continue With Event'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Step1'
      Type                = 'IdLE.Step.ContinuePreconditionEvent'
      Precondition        = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
        )
      }
      OnPreconditionFalse = 'Continue'
      PreconditionEvent   = @{
        Type    = 'PolicyAdvisory'
        Message = 'Step skipped due to policy advisory'
        Data    = @{ Hint = 'BYOD check not met' }
      }
    }
  )
}
