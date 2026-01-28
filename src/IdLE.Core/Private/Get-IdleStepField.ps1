Set-StrictMode -Version Latest

function Get-IdleStepField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Step) { return $null }

    if ($Step -is [System.Collections.IDictionary]) {
        if ($Step.Contains($Name)) {
            return $Step[$Name]
        }
        return $null
    }

    $propNames = @($Step.PSObject.Properties.Name)
    if ($propNames -contains $Name) {
        return $Step.$Name
    }

    return $null
}
