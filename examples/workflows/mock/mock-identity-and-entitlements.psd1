@{
    Name           = 'Mock Provider - Identity + Entitlements (Demo)'
    LifecycleEvent = 'Joiner'
    Description    = 'Demonstrates using the Mock provider to set attributes and group entitlements without touching real systems.'

    Steps          = @(
        @{
            Name = 'Ensure user attributes (mock)'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                Provider    = 'Identity'
                IdentityKey = '{{Request.Input.IdentityKey}}'
                Attributes  = @{
                    GivenName   = '{{Request.Input.GivenName}}'
                    Surname     = '{{Request.Input.Surname}}'
                    Department  = '{{Request.Input.Department}}'
                    Title       = '{{Request.Input.Title}}'
                }
            }
        }

        @{
            Name = 'Ensure group memberships (mock)'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                Provider    = 'Identity'
                IdentityKey = '{{Request.Input.IdentityKey}}'

                # In the mock provider, entitlements are just stored in-memory.
                # Use this to validate your workflow logic and template placeholders.
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = '{{Request.Input.GroupId}}'
                    DisplayName = '{{Request.Input.GroupName}}'
                }
                State       = 'Present'
            }
        }

        @{
            Name = 'Emit completion'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mock demo completed for {{Request.Input.IdentityKey}}.'
            }
        }
    )
}
