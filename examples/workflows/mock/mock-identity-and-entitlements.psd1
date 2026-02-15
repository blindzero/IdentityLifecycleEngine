@{
    Name           = 'Mock Provider - OnFailure handling (Demo)'
    LifecycleEvent = 'Joiner'
    Description    = 'Demonstrates OnFailureSteps for cleanup/notification when primary steps fail (using Mock provider).'

    Steps          = @(
        @{
            Name = 'Emit start'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Starting workflow with OnFailure handling.'
            }
        }

        @{
            Name = 'Primary action (will fail intentionally)'
            Type = 'IdLE.Step.Fail'
            With = @{
                Message = 'Intentional failure to demonstrate OnFailureSteps.'
            }

            OnFailureSteps = @(
                @{
                    Name = 'Emit failure notification'
                    Type = 'IdLE.Step.EmitEvent'
                    With = @{
                        Message = 'Primary action failed for {{Request.Input.IdentityKey}}.'
                    }
                }
            )
        }
    )
}
