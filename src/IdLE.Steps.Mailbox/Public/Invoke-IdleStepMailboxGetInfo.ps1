function Invoke-IdleStepMailboxGetInfo {
    <#
    .SYNOPSIS
    Retrieves mailbox details and returns a structured report.

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider
    (default 'ExchangeOnline') as -Provider. The provider implements a GetMailbox
    method with the signature (IdentityKey, AuthSession) and return a mailbox object.

    The step is read-only and returns Changed = $false.

    Authentication is handled by the engine: without With.AuthSessionName the session is named after the
    provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog).

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .OUTPUTS
    System.Collections.Hashtable (State.Mailbox)

    .EXAMPLE
    # In workflow definition:
    @{
        Name = 'Get mailbox info'
        Type = 'IdLE.Step.Mailbox.GetInfo'
        With = @{
            Provider      = 'ExchangeOnline'
            IdentityKey   = 'user@contoso.com'
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

    $result = $Provider.Invoke('GetMailbox', @($With.IdentityKey))

    # Mailbox data for downstream steps.
    return @{ State = @{ Mailbox = $result } }
}
