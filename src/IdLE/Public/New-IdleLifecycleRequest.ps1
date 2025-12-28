function New-IdleLifecycleRequest {
    <#
    .SYNOPSIS
    Creates a lifecycle request object.

    .DESCRIPTION
    Creates an IdLE lifecycle request representing business intent (e.g. Joiner/Mover/Leaver).
    This is a stub in the core skeleton increment and will be implemented in subsequent commits.

    .PARAMETER LifecycleEvent
    The lifecycle event name (e.g. Joiner, Mover, Leaver).

    .PARAMETER Actor
    The actor who initiated the request (required).

    .PARAMETER CorrelationId
    A correlation identifier for audit/event correlation (required).

    .PARAMETER IdentityKeys
    A hashtable of system-neutral identity keys (e.g. EmployeeId, UPN, ObjectId).

    .PARAMETER DesiredState
    A hashtable describing the desired state (attributes, entitlements, etc.).

    .PARAMETER Changes
    Optional hashtable describing changes (typically used for Mover lifecycle events).

    .EXAMPLE
    New-IdleLifecycleRequest -LifecycleEvent Joiner -Actor 'alice@contoso.com' -CorrelationId (New-Guid)

    .OUTPUTS
    System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LifecycleEvent,

        [Parameter(Mandatory)]
        [string] $Actor,

        [Parameter(Mandatory)]
        [string] $CorrelationId,

        [Parameter()]
        [hashtable] $IdentityKeys = @{},

        [Parameter()]
        [hashtable] $DesiredState = @{},

        [Parameter()]
        [hashtable] $Changes
    )

    throw 'Not implemented: New-IdleLifecycleRequest will be implemented in IdLE.Core in a subsequent increment.'
}
