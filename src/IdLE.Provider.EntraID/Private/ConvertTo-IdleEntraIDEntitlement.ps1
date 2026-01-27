Set-StrictMode -Version Latest

function ConvertTo-IdleEntraIDEntitlement {
    <#
    .SYNOPSIS
    Converts a value to an IdLE.Entitlement object for Entra ID provider.

    .DESCRIPTION
    Normalizes and validates entitlement values from various input formats
    (hashtable, PSCustomObject) into a standard IdLE.Entitlement object.

    The function validates that required fields (Kind, Id) are present and not empty.
    Supports optional fields: DisplayName, Mail.

    .PARAMETER Value
    The input value to convert. Can be a hashtable or PSCustomObject with
    Kind, Id, and optionally DisplayName and Mail properties.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.Entitlement'
    - PSTypeName: 'IdLE.Entitlement'
    - Kind: Entitlement kind (e.g., 'Group')
    - Id: Entitlement identifier (e.g., Group objectId)
    - DisplayName: Optional display name (null if not provided or empty)
    - Mail: Optional mail address (null if not provided or empty)

    .EXAMPLE
    $ent = ConvertTo-IdleEntraIDEntitlement -Value @{ Kind = 'Group'; Id = '12345678-1234-1234-1234-123456789012' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value
    )

    $kind = $null
    $id = $null
    $displayName = $null
    $mail = $null

    if ($Value -is [System.Collections.IDictionary]) {
        $kind = $Value['Kind']
        $id = $Value['Id']
        if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
        if ($Value.Contains('Mail')) { $mail = $Value['Mail'] }
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
        if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
        if ($props.Name -contains 'Mail') { $mail = $Value.Mail }
    }

    if ([string]::IsNullOrWhiteSpace([string]$kind)) {
        throw "Entitlement.Kind must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "Entitlement.Id must not be empty."
    }

    return [pscustomobject]@{
        PSTypeName  = 'IdLE.Entitlement'
        Kind        = [string]$kind
        Id          = [string]$id
        DisplayName = if ($null -eq $displayName -or [string]::IsNullOrWhiteSpace([string]$displayName)) {
            $null
        }
        else {
            [string]$displayName
        }
        Mail        = if ($null -eq $mail -or [string]::IsNullOrWhiteSpace([string]$mail)) {
            $null
        }
        else {
            [string]$mail
        }
    }
}
