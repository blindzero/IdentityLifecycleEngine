function New-IdleLifecycleRequestCore {
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

    # Construct and return the core domain object defined in Private/IdleLifecycleRequest.ps1
    return [IdleLifecycleRequest]::new(
        $LifecycleEvent,
        $IdentityKeys,
        $DesiredState,
        $Changes,
        $CorrelationId,
        $Actor
    )
}
