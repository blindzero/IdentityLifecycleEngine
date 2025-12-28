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
    Assert-IdleNoScriptBlock -Value $IdentityKeys -Path 'IdentityKeys'
    Assert-IdleNoScriptBlock -Value $DesiredState -Path 'DesiredState'
    Assert-IdleNoScriptBlock -Value $Changes      -Path 'Changes'

    # Clone hashtables to avoid external mutation after object creation
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
