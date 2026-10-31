@{
  Name           = 'Missing Context Path At Invoke'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name         = 'Step1'
      Type         = 'Test.IdLE.Step.MissingContextAtInvoke'
      Precondition = @{
        All = @(
          @{ In = @{ Path = 'Request.Context.NA'; Values = @('EU', 'DE') } }
        )
      }
    }
  )
}
