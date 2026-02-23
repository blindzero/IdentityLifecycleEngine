@{
  Name           = 'Invalid Precondition Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'IdLE.Step.InvalidPreconditionSchema'
      Preconditions = @(
        @{
          UnknownKey = 'bad'
        }
      )
    }
  )
}
