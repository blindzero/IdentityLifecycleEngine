function New-IdleRequest {
    <#
    .SYNOPSIS
    Creates a lifecycle request object.

    .DESCRIPTION
    Creates and normalizes an IdLE LifecycleRequest representing business intent
    (e.g. Joiner/Mover/Leaver). CorrelationId is generated if missing. Actor is optional.
    Changes is optional and stays $null when omitted.

    .PARAMETER LifecycleEvent
    The lifecycle event name (e.g. Joiner, Mover, Leaver).

    .PARAMETER CorrelationId
    Correlation identifier for audit/event correlation. Generated if missing.

    .PARAMETER Actor
    Optional actor claim who initiated the request. Not required by the core engine in V1.

    .PARAMETER IdentityKeys
    A hashtable of system-neutral identity keys (e.g. EmployeeId, UPN, ObjectId).

    .PARAMETER DesiredState
    A hashtable describing the desired state (attributes, entitlements, etc.).

    .PARAMETER Changes
    Optional hashtable describing changes (typically used for Mover lifecycle events).

    .EXAMPLE
    New-IdleRequest -LifecycleEvent Joiner -CorrelationId (New-Guid) -IdentityKeys @{ EmployeeId = '12345' }

    .OUTPUTS
    IdleLifecycleRequest
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LifecycleEvent,

        [Parameter()]
        [string] $CorrelationId,

        [Parameter()]
        [string] $Actor,

        [Parameter()]
        [hashtable] $IdentityKeys = @{},

        [Parameter()]
        [hashtable] $DesiredState = @{},

        [Parameter()]
        [hashtable] $Changes
    )

    # Use core-exported factory to construct the domain object. Keeps domain model inside IdLE.Core.
    New-IdleRequestObject @PSBoundParameters
}

