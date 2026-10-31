@{
  Name           = 'Invalid Precondition Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'Step1'
      Type          = 'Test.IdLE.Step.InvalidPreconditionSchema'
      Precondition = @{
        All = @(
        @{
          UnknownKey = 'bad'
        }
        )
      }
    }
  )
}
