Set-StrictMode -Version Latest

function ConvertTo-IdleRequiredCapabilities {
    <#
    .SYNOPSIS
    Normalizes the optional RequiresCapabilities key from a workflow step.

    .DESCRIPTION
    Supported shapes:
    - missing / $null -> empty list
    - string -> single capability
    - array/enumerable of strings -> list of capabilities

    The output is a stable, sorted, unique string array.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName
    )

    if ($null -eq $Value) {
        return @()
    }

    $items = @()

    if ($Value -is [string]) {
        $items = @($Value)
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($v in $Value) {
            $items += $v
        }
    }
    else {
        throw [System.ArgumentException]::new(
            ("Workflow step '{0}' has invalid RequiresCapabilities value. Expected string or string array." -f $StepName),
            'Workflow'
        )
    }

    $normalized = @()
    foreach ($c in $items) {
        if ($null -eq $c) {
            continue
        }

        $s = ConvertTo-IdleCapabilityIdentifier -Value $c
        if ($null -eq $s) {
            continue
        }

        # Keep convention aligned with Get-IdleProviderCapabilities:
        # - dot-separated segments
        # - no whitespace
        # - starts with a letter
        if (-not (Test-IdleCapabilityIdentifier -Capability $s)) {
            throw [System.ArgumentException]::new(
                ("Workflow step '{0}' declares invalid capability '{1}'. Expected dot-separated segments like 'IdLE.Identity.Read'." -f $StepName, $s),
                'Workflow'
            )
        }

        # Normalize deprecated capabilities
        $normalized += ConvertTo-IdleNormalizedCapability -Capability $s
    }

    return @($normalized | Sort-Object -Unique)
}
