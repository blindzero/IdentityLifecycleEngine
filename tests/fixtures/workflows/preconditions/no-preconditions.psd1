@{
  Name           = 'No Preconditions'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Step1'
      Type = 'IdLE.Step.NoPrecondition'
    }
  )
}
