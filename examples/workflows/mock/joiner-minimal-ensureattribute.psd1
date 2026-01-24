@{
  Name           = 'Joiner - Minimal (EnsureAttribute)'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Joiner workflow started (minimalpack).'
      }
    }

    @{
      Name = 'Ensure Department'
      Type = 'IdLE.Step.EnsureAttribute'
      With = @{
        Provider    = 'Identity'
        IdentityKey = 'user1'
        Name        = 'Department'
        Value       = 'IT'
      }
    }

    @{
      Name = 'Emit done'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Joiner workflow completed (minimalpack).'
      }
    }
  )
}
