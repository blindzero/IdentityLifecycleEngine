Set-StrictMode -Version Latest

function Test-IdleWorkflowStepKey {
    <#
    .SYNOPSIS
    Checks whether a workflow step contains a given key.
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
        return $Step.ContainsKey($Key)
    }

    $m = $Step | Get-Member -Name $Key -MemberType NoteProperty, Property -ErrorAction SilentlyContinue
    return ($null -ne $m)
}
