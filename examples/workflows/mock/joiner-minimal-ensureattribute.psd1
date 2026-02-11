@{
  Name           = 'Joiner - Minimal (EnsureAttributes)'
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
      Type = 'IdLE.Step.EnsureAttributes'
      With = @{
        Provider    = 'Identity'
        IdentityKey = 'user1'
        Attributes  = @{
          Department = 'IT'
        }
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
