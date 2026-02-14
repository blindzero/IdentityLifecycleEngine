function Copy-IdleRedactedObject {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RedactionMarker', Justification = 'Used within nested helper functions for redaction output.')]
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

    # Default key list aligned with Issue #48 acceptance criteria.
    # Keep this list conservative (exact match) to avoid accidental over-redaction.
    # Note: These fields are redacted when objects pass through logging/eventing paths.
    # They do NOT prevent direct access when explicitly requested (e.g., AllowPlainTextPasswordOutput).
    # Redaction protects against accidental leakage, not intentional access by callers.
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
        'privateKey',
        'AccountPassword',
        'AccountPasswordAsPlainText',
        'GeneratedAccountPasswordPlainText',
        'GeneratedAccountPasswordProtected'
    )

    $effectiveKeys = if ($null -ne $RedactedKeys -and $RedactedKeys.Count -gt 0) {
        $RedactedKeys
    }
    else {
        $defaultKeys
    }

    # Use a reference-based visit set to avoid runaway recursion for cyclic graphs.
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

    function Get-IdlePrimaryTypeName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Object
        )

        # Preserve the original PSTypeName when present (e.g., 'IdLE.Event').
        # We intentionally skip default CLR / PowerShell type names.
        foreach ($t in $Object.PSObject.TypeNames) {
            if ([string]::IsNullOrWhiteSpace($t)) {
                continue
            }

            if ($t -eq 'System.Object' -or
                $t -eq 'System.Management.Automation.PSCustomObject' -or
                $t -like 'System.*') {
                continue
            }

            return $t
        }

        return $null
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

        # Redact ScriptBlocks to avoid complex nested structures and potential cycles
        if ($InnerValue -is [scriptblock]) {
            return $RedactionMarker
        }

        # Primitive / immutable-ish types can be returned as-is.
        if (Test-IdlePrimitiveValue -Value $InnerValue) {
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
        if (Test-IdleEnumerableValue -Value $InnerValue) {
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

            # Preserve PSTypeName for objects like IdLE.Event to keep tests and consumers stable.
            $primaryType = Get-IdlePrimaryTypeName -Object $InnerValue
            if ($null -ne $primaryType) {
                $map.PSTypeName = $primaryType
            }

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
