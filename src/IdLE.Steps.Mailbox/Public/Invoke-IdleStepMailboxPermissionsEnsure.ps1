function Invoke-IdleStepMailboxPermissionsEnsure {
    <#
    .SYNOPSIS
    Ensures that mailbox delegate permissions match the desired state.

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider
    (default 'ExchangeOnline') as -Provider. The provider implements an EnsureMailboxPermissions
    method with the signature (IdentityKey, Permissions, AuthSession) and return an object
    that contains a boolean property 'Changed'.

    The step is idempotent by design: it converges mailbox delegate permissions to the desired
    state by computing the delta between current and desired permissions and applying only the
    necessary changes.

    Supported rights (v1):
    - FullAccess
    - SendAs
    - SendOnBehalf

    Permissions array shape (data-only):
    Each entry must be a hashtable with:
    - AssignedUser: string (required) - UPN or SMTP address of the delegate
    - Right: 'FullAccess' | 'SendAs' | 'SendOnBehalf' (required)
    - Ensure: 'Present' | 'Absent' (required)

    Authentication is handled by the engine: without With.AuthSessionName the session is named after the
    provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog).

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .OUTPUTS
    System.Collections.Hashtable (Changed)

    .EXAMPLE
    # In workflow definition (grant FullAccess and SendAs):
    @{
        Name = 'Set Shared Mailbox Permissions'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'shared@contoso.com'
            Permissions = @(
                @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
                @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs';     Ensure = 'Present' }
            )
        }
    }

    .EXAMPLE
    # In workflow definition (revoke access):
    @{
        Name = 'Revoke Mailbox Access'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'shared@contoso.com'
            Permissions = @(
                @{ AssignedUser = 'leaver@contoso.com'; Right = 'FullAccess';   Ensure = 'Absent' }
                @{ AssignedUser = 'leaver@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Absent' }
            )
        }
    }

    .EXAMPLE
    # With dynamic identity from request:
    @{
        Name = 'Grant Team Mailbox Access'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'team@contoso.com'
            Permissions = @(
                @{ AssignedUser = '{{Request.Intent.UserPrincipalName}}'; Right = 'FullAccess'; Ensure = 'Present' }
            )
        }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider
    )

    $result = $Provider.Invoke('EnsureMailboxPermissions', @($With.IdentityKey, $With.Permissions))

    $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
    return @{ Changed = $changed }
}
