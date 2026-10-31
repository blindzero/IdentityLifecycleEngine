@{
  Name           = 'No Preconditions'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Step1'
      Type = 'Test.IdLE.Step.NoPrecondition'
    }
  )
}
