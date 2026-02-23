@{
  Name           = 'Invalid Preconditions Single Hashtable'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.InvalidPCSingleHt'
      Preconditions = @{
        Equals = @{
          Path  = 'Plan.LifecycleEvent'
          Value = 'Joiner'
        }
      }
    }
  )
}
