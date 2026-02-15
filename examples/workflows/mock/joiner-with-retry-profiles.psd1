@{
    # Mock example workflow demonstrating configurable retry behavior
    #
    # This workflow is designed to run with the Mock/File providers
    # and therefore uses only generic, provider-agnostic steps.

    Name           = 'Joiner - With Retry Profiles (Mock)'
    LifecycleEvent = 'Joiner'
    Description    = 'Mock workflow showing RetryProfile usage across steps with different retry characteristics.'

    Steps = @(
        @{
            Name        = 'Emit start'
            Type        = 'IdLE.Step.EmitEvent'
            Description = 'Start marker event (Default retry profile)'
            With        = @{
                Message = 'Joiner workflow started (mock retry profiles demo).'
            }
        }

        @{
            Name         = 'Ensure baseline attributes'
            Type         = 'IdLE.Step.EnsureAttributes'
            Description  = 'Simulate a system with stricter throttling (GraphAPI profile)'
            RetryProfile = 'GraphAPI'
            With         = @{
                Provider    = 'Identity'
                IdentityKey = 'user1'
                Attributes  = @{
                    Department = 'IT'
                    Title      = 'Engineer'
                }
            }
        }

        @{
            Name         = 'Ensure mailbox entitlement'
            Type         = 'IdLE.Step.EnsureEntitlement'
            Description  = 'Simulate a slower system (ExchangeOnline profile)'
            RetryProfile = 'ExchangeOnline'
            With         = @{
                Provider    = 'Identity'
                IdentityKey = 'user1'
                Entitlement = @{
                    Kind        = 'Mailbox'
                    Id          = 'UserMailbox'
                    DisplayName = 'User Mailbox'
                }
                State       = 'Present'
            }
        }

        @{
            Name         = 'Ensure group membership'
            Type         = 'IdLE.Step.EnsureEntitlement'
            Description  = 'Simulate Graph-like throttling again (GraphAPI profile)'
            RetryProfile = 'GraphAPI'
            With         = @{
                Provider    = 'Identity'
                IdentityKey = 'user1'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'demo-group'
                    DisplayName = 'Demo Group'
                }
                State       = 'Present'
            }
        }

        @{
            Name         = 'Emit done'
            Type         = 'IdLE.Step.EmitEvent'
            Description  = 'Completion marker event (Default retry profile)'
            With         = @{
                Message = 'Joiner workflow completed (mock retry profiles demo).'
            }
        }
    )

    OnFailureSteps = @(
        @{
            Name         = 'Emit failure notification'
            Type         = 'IdLE.Step.EmitEvent'
            Description  = 'Notify on workflow failure (Notifications profile)'
            RetryProfile = 'Notifications'
            With         = @{
                Message = 'ALERT: Joiner workflow failed for user1 (mock retry profiles demo).'
            }
        }
    )
}

<# 
Example ExecutionOptions configuration:

$executionOptions = @{
    RetryProfiles = @{
        Default = @{
            MaxAttempts              = 3
            InitialDelayMilliseconds = 200
            BackoffFactor            = 2.0
            MaxDelayMilliseconds     = 5000
            JitterRatio              = 0.2
        }
        GraphAPI = @{
            MaxAttempts              = 5
            InitialDelayMilliseconds = 1000
            BackoffFactor            = 2.0
            MaxDelayMilliseconds     = 16000
            JitterRatio              = 0.3
        }
        ExchangeOnline = @{
            MaxAttempts              = 6
            InitialDelayMilliseconds = 500
            BackoffFactor            = 2.5
            MaxDelayMilliseconds     = 30000
            JitterRatio              = 0.25
        }
        Notifications = @{
            MaxAttempts              = 3
            InitialDelayMilliseconds = 100
            BackoffFactor            = 1.5
            MaxDelayMilliseconds     = 1000
            JitterRatio              = 0.1
        }
    }
    DefaultRetryProfile = 'Default'
}

# Each step uses:
# - Default profile if RetryProfile is not set
# - Named profile if RetryProfile is set on the step
#>
