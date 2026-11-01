function Invoke-IdleStepMailboxTypeEnsure {
    <#
    .SYNOPSIS
    Ensures that a mailbox is of the desired type (User, Shared, Room, Equipment).

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider
    (default 'ExchangeOnline') as -Provider. The provider implements an EnsureMailboxType
    method with the signature (IdentityKey, MailboxType, AuthSession) and return an object
    that contains a boolean property 'Changed'.

    The step is idempotent by design: it converges state to the desired type.

    Supported mailbox types:
    - User (regular user mailbox)
    - Shared (shared mailbox for team use)
    - Room (room resource mailbox)
    - Equipment (equipment resource mailbox)

    Authentication is handled by the engine: without With.AuthSessionName the session is named after the
    provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog).

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .OUTPUTS
    System.Collections.Hashtable (Changed)

    .EXAMPLE
    # In workflow definition (convert to shared mailbox):
    @{
        Name = 'Convert to shared mailbox'
        Type = 'IdLE.Step.Mailbox.EnsureType'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'user@contoso.com'
            MailboxType = 'Shared'
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

    $result = $Provider.Invoke('EnsureMailboxType', @($With.IdentityKey, $With.MailboxType))

    $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
    return @{ Changed = $changed }
}
