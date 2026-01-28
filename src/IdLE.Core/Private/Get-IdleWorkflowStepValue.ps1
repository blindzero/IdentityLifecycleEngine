Set-StrictMode -Version Latest

function Get-IdleWorkflowStepValue {
    <#
    .SYNOPSIS
    Gets a value from a workflow step by key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    if ($Step -is [System.Collections.IDictionary]) {
        return $Step[$Key]
    }

    return $Step.$Key
}
