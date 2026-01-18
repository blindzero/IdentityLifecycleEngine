Set-StrictMode -Version Latest

function ConvertTo-IdleCanonicalCapability {
    <#
    .SYNOPSIS
    Normalizes capability names to their canonical form and emits warnings for legacy names.

    .DESCRIPTION
    This function converts legacy Identity.* capability names to their canonical IdLE.Identity.* form.
    
    When a legacy capability name is encountered, a warning event is emitted through the provided
    event sink (if available) to inform users they should migrate to the canonical form.
    
    This maintains backward compatibility while encouraging migration to the canonical namespace.

    .PARAMETER Capability
    The capability string to normalize.

    .PARAMETER EventSink
    Optional event sink for emitting deprecation warnings. If not provided, warnings are not emitted.

    .OUTPUTS
    System.String - The normalized capability name.

    .NOTES
    Legacy capability names are supported until v1.0.0 for backward compatibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink
    )

    # Mapping of legacy capability names to canonical names
    $legacyToCanonical = @{
        'Identity.Read'              = 'IdLE.Identity.Read'
        'Identity.Disable'           = 'IdLE.Identity.Disable'
        'Identity.Enable'            = 'IdLE.Identity.Enable'
        'Identity.Create'            = 'IdLE.Identity.Create'
        'Identity.Delete'            = 'IdLE.Identity.Delete'
        'Identity.Move'              = 'IdLE.Identity.Move'
        'Identity.List'              = 'IdLE.Identity.List'
        'Identity.Attribute.Ensure'  = 'IdLE.Identity.Attribute.Ensure'
        'Identity.EnsureAttribute'   = 'IdLE.Identity.Attribute.Ensure'
    }

    # Check if this is a legacy capability name
    if ($legacyToCanonical.ContainsKey($Capability)) {
        $canonicalName = $legacyToCanonical[$Capability]
        
        # Emit warning event if EventSink is available
        if ($null -ne $EventSink) {
            $eventMessage = "Legacy capability name '$Capability' is deprecated and will be removed in v1.0.0. Use '$canonicalName' instead."
            
            # Check if EventSink has WriteEvent method
            if ($EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                try {
                    $EventSink.WriteEvent('Warning', $eventMessage, 'CapabilityNormalization', @{
                        LegacyName = $Capability
                        CanonicalName = $canonicalName
                    })
                }
                catch {
                    # Silently continue if event emission fails
                    # This ensures capability normalization isn't blocked by event sink issues
                }
            }
        }
        
        return $canonicalName
    }

    # Return the capability as-is if it's already canonical or not a known legacy name
    return $Capability
}
