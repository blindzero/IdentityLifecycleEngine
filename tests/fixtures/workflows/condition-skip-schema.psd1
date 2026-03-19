@{
  Name           = 'Condition Skip Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'StrictStep'
      Type      = 'IdLE.Step.StrictSchemaTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
    }
  )
}
