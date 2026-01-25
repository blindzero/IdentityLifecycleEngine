@{
    # Example workflow demonstrating configurable retry behavior
    #
    # This workflow shows how to use RetryProfile to configure
    # different retry behavior for steps targeting different systems.

    Name           = 'Joiner - With Retry Profiles'
    LifecycleEvent = 'Joiner'
    Description    = 'Example workflow with custom retry profiles for different target systems'

    Steps = @(
        @{
            Name        = 'Resolve identity from HR system'
            Type        = 'IdLE.Step.ResolveIdentity'
            Description = 'Lookup user in HR database'
            # Uses default retry profile (or no retry if not configured)
        }

        @{
            Name         = 'Create Entra ID account'
            Type         = 'IdLE.Step.CreateIdentity'
            Description  = 'Create user in Entra ID (Microsoft Graph API)'
            RetryProfile = 'GraphAPI'
            # Microsoft Graph has specific throttling limits - use a profile
            # optimized for Graph API retry behavior
        }

        @{
            Name         = 'Create mailbox'
            Type         = 'IdLE.Step.EnsureEntitlement'
            Description  = 'Provision Exchange Online mailbox'
            RetryProfile = 'ExchangeOnline'
            With         = @{
                Kind       = 'Mailbox'
                MailboxType = 'UserMailbox'
            }
            # Exchange Online has different throttling characteristics
            # than Graph - use a dedicated profile
        }

        @{
            Name         = 'Add to security group'
            Type         = 'IdLE.Step.EnsureEntitlement'
            Description  = 'Add user to Entra ID security group'
            RetryProfile = 'GraphAPI'
            With         = @{
                Kind  = 'Group'
                Value = 'All_Users'
            }
        }

        @{
            Name         = 'Set manager attribute'
            Type         = 'IdLE.Step.EnsureAttribute'
            Description  = 'Set manager reference in Entra ID'
            RetryProfile = 'GraphAPI'
            With         = @{
                AttributeName = 'manager'
                Value         = '{{Request.Data.ManagerId}}'
            }
        }
    )

    OnFailureSteps = @(
        @{
            Name         = 'Emit failure notification'
            Type         = 'IdLE.Step.EmitEvent'
            Description  = 'Notify on workflow failure'
            RetryProfile = 'Notifications'
            # Notification systems may have their own rate limits
            With         = @{
                Message = 'Joiner workflow failed for user {{Request.Data.UserPrincipalName}}'
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
            # Microsoft Graph throttling can be aggressive
            # Use more retries with longer delays
            MaxAttempts              = 5
            InitialDelayMilliseconds = 1000
            BackoffFactor            = 2.0
            MaxDelayMilliseconds     = 16000
            JitterRatio              = 0.3
        }
        ExchangeOnline = @{
            # Exchange Online often requires patience
            MaxAttempts              = 6
            InitialDelayMilliseconds = 500
            BackoffFactor            = 2.5
            MaxDelayMilliseconds     = 30000
            JitterRatio              = 0.25
        }
        Notifications = @{
            # Notifications should retry but not delay the workflow too much
            MaxAttempts              = 3
            InitialDelayMilliseconds = 100
            BackoffFactor            = 1.5
            MaxDelayMilliseconds     = 1000
            JitterRatio              = 0.1
        }
    }
    DefaultRetryProfile = 'Default'
}

# Invoke the plan with retry configuration
$result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $executionOptions

# Each step will use its configured retry profile:
# - Steps without RetryProfile use 'Default' (from DefaultRetryProfile)
# - Steps with RetryProfile='GraphAPI' use the GraphAPI profile
# - Steps with RetryProfile='ExchangeOnline' use the ExchangeOnline profile
# - Steps with RetryProfile='Notifications' use the Notifications profile
#>
