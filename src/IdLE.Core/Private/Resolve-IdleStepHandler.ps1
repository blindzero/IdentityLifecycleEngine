function Resolve-IdleStepHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepType,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Registry
    )

    # Registry maps StepType -> handler.
    #
    # Trust boundary:
    # - The registry is a host-controlled extension point and must be treated as trusted input.
    # - Workflows must never be able to provide code (ScriptBlocks) that is executed by the engine.
    #
    # Security / secure defaults:
    # - Only string handlers (function names) are supported.
    # - ScriptBlock handlers are intentionally rejected to avoid arbitrary code execution.

    if (-not $Registry.ContainsKey($StepType)) {
        return $null
    }

    $handler = $Registry[$StepType]

    if ($handler -is [string]) {
        $fn = $handler.Trim()
        if ([string]::IsNullOrWhiteSpace($fn)) {
            return $null
        }

        # Ensure the function exists in the current session.
        # The host is responsible for importing the module that provides the handler.
        $cmd = Get-Command -Name $fn -ErrorAction SilentlyContinue
        if ($null -eq $cmd) {
            return $null
        }

        return $cmd.Name
    }

    if ($handler -is [scriptblock]) {
        throw [System.ArgumentException]::new(
            "Invalid step handler for type '$StepType'. ScriptBlock handlers are not allowed. Provide a string with a function name instead.",
            'Registry'
        )
    }

    # Any other type is invalid configuration.
    throw [System.ArgumentException]::new(
        "Invalid step handler for type '$StepType'. Allowed: string (function name).",
        'Registry'
    )
}
