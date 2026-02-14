Set-StrictMode -Version Latest

function Test-IdleCapabilityIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability
    )

    return ($Capability -match '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$')
}
