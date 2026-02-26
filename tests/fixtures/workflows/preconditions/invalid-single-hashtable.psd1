@{
  Name           = 'Invalid Preconditions Single Hashtable'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.InvalidPCSingleHt'
      Precondition = @{
        Equals = @{
          Path  = 'Plan.LifecycleEvent'
          Value = 'Joiner'
        }
      }
    }
  )
}
