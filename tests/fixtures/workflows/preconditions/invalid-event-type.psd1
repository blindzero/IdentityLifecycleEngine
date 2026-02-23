@{
  Name           = 'Invalid PreconditionEvent Type'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name              = 'Step1'
      Type              = 'IdLE.Step.InvalidPCEvt'
      Preconditions     = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
      PreconditionEvent = @{
        Message = 'Some message'
      }
    }
  )
}
