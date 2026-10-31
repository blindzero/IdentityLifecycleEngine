@{
  Name           = 'Condition Skip Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'StrictStep'
      Type      = 'Test.IdLE.Step.StrictSchemaTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
    }
  )
}
