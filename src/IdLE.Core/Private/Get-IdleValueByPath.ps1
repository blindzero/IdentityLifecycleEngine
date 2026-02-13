function Get-IdleValueByPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # Supports dotted property paths, e.g. "DesiredState.Department"
    $current = $Object
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $null }

        $current = Get-IdlePropertyValue -Object $current -Name $segment
        if ($null -eq $current) { return $null }
    }

    return $current
}
