function New-IdleLifecycleRequestObject {
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

    # Validate that no ScriptBlocks are present in the input data
    Assert-IdleNoScriptBlock -InputObject $IdentityKeys -Path 'IdentityKeys'
    Assert-IdleNoScriptBlock -InputObject $DesiredState -Path 'DesiredState'
    Assert-IdleNoScriptBlock -InputObject $Changes      -Path 'Changes'

    # Clone hashtables to avoid external mutation after object creation
    # shallow clone is sufficient as we have already validated no ScriptBlocks are present
    $IdentityKeys = if ($null -eq $IdentityKeys) { @{} } else { $IdentityKeys.Clone() }
    $DesiredState = if ($null -eq $DesiredState) { @{} } else { $DesiredState.Clone() }
    $Changes      = if ($null -eq $Changes) { $null } else { $Changes.Clone() }

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
