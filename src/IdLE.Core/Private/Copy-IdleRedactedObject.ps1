function Copy-IdleRedactedObject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [AllowNull()]
        [string[]] $RedactedKeys,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RedactionMarker = '[REDACTED]'
    )

    # Default key list aligned with the Issue #48 acceptance criteria.
    # Keep this list conservative (exact match) to avoid accidental over-redaction.
    $defaultKeys = @(
        'password',
        'passphrase',
        'secret',
        'token',
        'apikey',
        'apiKey',
        'clientSecret',
        'accessToken',
        'refreshToken',
        'credential',
        'privateKey'
    )

    $effectiveKeys = if ($null -ne $RedactedKeys -and $RedactedKeys.Count -gt 0) {
        $RedactedKeys
    }
    else {
        $defaultKeys
    }

    # Use a reference-based visit set to avoid runaway recursion for cyclic graphs.
    # We store RuntimeHelpers hash codes for reference identity.
    $visited = [System.Collections.Generic.HashSet[int]]::new()

    function Test-IdleRedactionKeyMatch {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        foreach ($k in $effectiveKeys) {
            if ($null -eq $k) {
                continue
            }

            if ([string]::Equals($Name, $k, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    function Copy-IdleRedactedInternal {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $InnerValue
        )

        if ($null -eq $InnerValue) {
            return $null
        }

        # Always redact sensitive runtime types regardless of key name.
        if ($InnerValue -is [pscredential] -or $InnerValue -is [securestring]) {
            return $RedactionMarker
        }

        # Primitive / immutable-ish types can be returned as-is.
        if ($InnerValue -is [string] -or
            $InnerValue -is [int] -or
            $InnerValue -is [long] -or
            $InnerValue -is [double] -or
            $InnerValue -is [decimal] -or
            $InnerValue -is [bool] -or
            $InnerValue -is [datetime] -or
            $InnerValue -is [guid]) {
            return $InnerValue
        }

        # Cycle protection for reference types that may contain nested structures.
        if (-not ($InnerValue -is [ValueType]) -and -not ($InnerValue -is [string])) {
            $refHash = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($InnerValue)
            if ($visited.Contains($refHash)) {
                # Conservative: do not try to represent cycles in exports/events.
                return $RedactionMarker
            }

            [void]$visited.Add($refHash)
        }

        # IDictionary -> clone recursively. Keep deterministic ordering where possible.
        if ($InnerValue -is [System.Collections.IDictionary]) {
            $isOrdered = $InnerValue -is [System.Collections.Specialized.OrderedDictionary]
            $copy = if ($isOrdered) { [ordered]@{} } else { @{} }

            $keys = @($InnerValue.Keys)

            if (-not $isOrdered) {
                # Deterministic ordering for regular dictionaries / hashtables.
                $keys = $keys | Sort-Object -Property { [string] $_ }
            }

            foreach ($k in $keys) {
                $keyName = [string] $k
                if (Test-IdleRedactionKeyMatch -Name $keyName) {
                    $copy[$k] = $RedactionMarker
                    continue
                }

                $copy[$k] = Copy-IdleRedactedInternal -InnerValue $InnerValue[$k]
            }

            return $copy
        }

        # Enumerables (except string) -> clone recursively.
        if ($InnerValue -is [System.Collections.IEnumerable] -and -not ($InnerValue -is [string])) {
            $items = @()
            foreach ($item in $InnerValue) {
                $items += Copy-IdleRedactedInternal -InnerValue $item
            }
            return $items
        }

        # Objects -> copy public properties into a stable PSCustomObject.
        $props = $InnerValue.PSObject.Properties |
            Where-Object { $_.MemberType -eq 'NoteProperty' -or $_.MemberType -eq 'Property' }

        if ($null -ne $props -and @($props).Count -gt 0) {
            $map = [ordered]@{}

            # Deterministic property order.
            foreach ($p in ($props | Sort-Object -Property Name)) {
                if (Test-IdleRedactionKeyMatch -Name $p.Name) {
                    $map[$p.Name] = $RedactionMarker
                    continue
                }

                $map[$p.Name] = Copy-IdleRedactedInternal -InnerValue $p.Value
            }

            return [pscustomobject] $map
        }

        # Fallback: keep representation stable without exporting runtime handles.
        return [string] $InnerValue
    }

    return Copy-IdleRedactedInternal -InnerValue $Value
}
