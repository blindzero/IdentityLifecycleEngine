Set-StrictMode -Version Latest

function Get-IdlePropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    # Check for direct property first (takes precedence over member-access enumeration)
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }

    # Support member-access enumeration: if Object is an array/list and items have the property,
    # return an array of all property values (mimics PowerShell's native behavior).
    if (($Object -is [System.Collections.IEnumerable]) -and -not ($Object -is [string])) {
        $items = @($Object)
        if ($items.Count -gt 0) {
            # Check if the first item has the property
            $firstItem = $items[0]
            if ($null -ne $firstItem) {
                $testProp = if ($firstItem -is [System.Collections.IDictionary]) {
                    if ($firstItem.Contains($Name)) { $Name } else { $null }
                } else {
                    if ($null -ne $firstItem.PSObject.Properties[$Name]) { $Name } else { $null }
                }

                if ($null -ne $testProp) {
                    # Extract the property from all items
                    $result = @()
                    foreach ($item in $items) {
                        if ($null -ne $item) {
                            $val = if ($item -is [System.Collections.IDictionary]) {
                                $item[$Name]
                            } else {
                                $p = $item.PSObject.Properties[$Name]
                                if ($null -ne $p) { $p.Value } else { $null }
                            }
                            $result += $val
                        }
                    }
                    return $result
                }
            }
        }
    }

    return $null
}
