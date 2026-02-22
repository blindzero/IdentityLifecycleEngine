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

    .PARAMETER Intent
    A hashtable containing the caller-provided action inputs for the workflow (attributes,
    entitlements, operator flags, etc.).

    .PARAMETER Context
    A hashtable containing read-only associated context provided by the host or resolvers
    (e.g. identity snapshots, device hints). Must not be treated as mutable state within IdLE.

    .PARAMETER Changes
    Optional hashtable describing changes (typically used for Mover lifecycle events).

    .EXAMPLE
    # Minimal Joiner request — CorrelationId is auto-generated, Intent/Context default to empty
    New-IdleRequest -LifecycleEvent Joiner -CorrelationId (New-Guid) -IdentityKeys @{ EmployeeId = '12345' }

    .EXAMPLE
    # Joiner request with caller-provided action inputs (Intent) and read-only associated context (Context)
    New-IdleRequest -LifecycleEvent Joiner -CorrelationId (New-Guid) -IdentityKeys @{ EmployeeId = '12345' } -Intent @{ Department = 'Engineering'; Title = 'Engineer' } -Context @{ Identity = @{ ObjectId = 'abc-123' } }

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
        [hashtable] $Intent = @{},

        [Parameter()]
        [hashtable] $Context = @{},

        [Parameter()]
        [hashtable] $Changes
    )

    # Use core-exported factory to construct the domain object. Keeps domain model inside IdLE.Core.
    New-IdleRequestObject @PSBoundParameters
}

