function Get-IdleIdentifierNamespaceError {
    <#
    .SYNOPSIS
    Checks an identifier against the namespace rules and returns an error message, or $null if valid.

    .DESCRIPTION
    Rules (see Data/ReservedNamespaces.psd1):
    - StepType: 'IdLE.*' only from first-party modules; extensions use '<Owner>.IdLE.Step.<...>'.
    - Capability: 'IdLE.*' only if defined by IdLE (or a deprecated alias); extensions use '<Owner>.IdLE.<Domain>.<Verb>'.

    Messages start with a stable error code (ReservedNamespace, InvalidExtensionNamespace, InvalidFirstPartyStepType, UnknownCapability).

    .PARAMETER Kind
    Identifier kind: StepType or Capability.

    .PARAMETER Identifier
    The identifier to check.

    .PARAMETER FirstParty
    The identifier is defined by a first-party module (StepType only).

    .OUTPUTS
    System.String (error message) or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('StepType', 'Capability')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Identifier,

        [Parameter()]
        [switch] $FirstParty
    )

    $rules = Get-IdleReservedNamespaces
    $kindRules = $rules[$Kind]
    $label = if ($Kind -eq 'StepType') { 'Step type' } else { 'Capability' }

    if ($Identifier.StartsWith($rules.ReservedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($Kind -eq 'Capability') {
            if ($kindRules.Defined -contains $Identifier -or $kindRules.Deprecated.ContainsKey($Identifier)) {
                return $null
            }

            $hint = "Extensions define their own capabilities as '<Owner>.IdLE.<Domain>.<Verb>', e.g. '$($kindRules.Example)'."
            return "UnknownCapability: Capability '$Identifier' is not defined by IdLE (see docs/reference/capabilities.md). $hint"
        }

        if ($FirstParty) {
            if ($Identifier -notmatch $kindRules.FirstPartyPattern) {
                return "InvalidFirstPartyStepType: Step type '$Identifier' must follow 'IdLE.Step.<Name>' or 'IdLE.Step.<Area>.<Name>'."
            }

            return $null
        }

        $suffix = $Identifier.Substring($rules.ReservedPrefix.Length)
        $hint = "Use '<Owner>.IdLE.$suffix', e.g. 'Contoso.IdLE.$suffix'."
        return "ReservedNamespace: $label '$Identifier' uses the reserved prefix '$($rules.ReservedPrefix)'. $hint"
    }

    if ($Identifier -notmatch $kindRules.ExtensionPattern) {
        return "InvalidExtensionNamespace: $label '$Identifier' must follow '<Owner>.IdLE.<...>', e.g. '$($kindRules.Example)'."
    }

    return $null
}
