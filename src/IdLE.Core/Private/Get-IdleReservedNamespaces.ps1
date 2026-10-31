function Get-IdleReservedNamespaces {
    <#
    .SYNOPSIS
    Returns the identifier namespace rules (Data/ReservedNamespaces.psd1).

    .DESCRIPTION
    The rules are data-only and loaded once per module session.

    .OUTPUTS
    Hashtable with ReservedPrefix and one entry per identifier kind (StepType, Capability).
    #>
    [CmdletBinding()]
    param()

    $rules = Get-Variable -Name 'IdleReservedNamespaces' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $rules) {
        $path = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Data/ReservedNamespaces.psd1'
        $rules = Import-PowerShellDataFile -LiteralPath $path
        Set-Variable -Name 'IdleReservedNamespaces' -Scope Script -Value $rules
    }

    return $rules
}
