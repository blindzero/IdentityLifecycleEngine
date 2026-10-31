Set-StrictMode -Version Latest

function ConvertTo-IdleCapabilityList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $Capabilities,

        [Parameter()]
        [switch] $Validate,

        [Parameter()]
        [switch] $Normalize,

        [Parameter()]
        [switch] $Unique,

        [Parameter()]
        [switch] $Sort,

        [Parameter()]
        [AllowEmptyString()]
        [string] $ErrorPrefix = 'Capability'
    )

    $items = @()

    foreach ($c in @($Capabilities)) {
        if ($null -eq $c) {
            continue
        }

        $s = ConvertTo-IdleCapabilityIdentifier -Value $c
        if ($null -eq $s) {
            continue
        }

        if ($Validate -and -not (Test-IdleCapabilityIdentifier -Capability $s)) {
            throw [System.ArgumentException]::new(
                "$ErrorPrefix '$s' is invalid. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                'Capabilities'
            )
        }

        if ($Validate) {
            # IdLE-defined capabilities or extension capabilities ('<Owner>.IdLE.*') only.
            $namespaceError = Get-IdleIdentifierNamespaceError -Kind 'Capability' -Identifier $s
            if ($null -ne $namespaceError) {
                throw [System.ArgumentException]::new("$namespaceError ($ErrorPrefix)", 'Capabilities')
            }
        }

        if ($Normalize) {
            $s = ConvertTo-IdleNormalizedCapability -Capability $s
        }

        $items += $s
    }

    if ($Unique) {
        $items = @($items | Sort-Object -Unique)
    }

    if ($Sort) {
        $items = @($items | Sort-Object)
    }

    return @($items)
}
