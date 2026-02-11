@{
    Name           = 'Joiner - With OnFailure Cleanup'
    LifecycleEvent = 'Joiner'
    Description    = 'Demonstrates OnFailureSteps for cleanup and notifications when primary steps fail'
    
    Steps          = @(
        @{
            Name = 'Emit start'
            Type = 'IdLE.Step.EmitEvent'
            With = @{ Message = 'Starting Joiner workflow with OnFailure handling' }
        }
        @{
            Name = 'Ensure Department'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{ 
                IdentityKey = 'user1'
                Attributes  = @{
                    Department = 'IT'
                }
                Provider    = 'Identity'
            }
        }
        @{
            Name = 'Assign demo group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{ 
                IdentityKey  = 'user1'
                Entitlement  = @{ 
                    Kind        = 'Group'
                    Id          = 'demo-group'
                    DisplayName = 'Demo Group'
                }
                State        = 'Present'
                Provider     = 'Identity'
            }
        }
    )

    OnFailureSteps = @(
        @{
            Name        = 'Log failure'
            Type        = 'IdLE.Step.EmitEvent'
            Description = 'Emits a custom event to log the failure'
            With        = @{ Message = 'Workflow execution failed - cleanup initiated' }
        }
        @{
            Name        = 'Notify administrator'
            Type        = 'IdLE.Step.EmitEvent'
            Description = 'Simulates sending a notification to administrators'
            With        = @{ Message = 'ALERT: Joiner workflow failed for user1 - manual intervention required' }
        }
    )
}
