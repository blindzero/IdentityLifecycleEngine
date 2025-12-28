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

    # Registry maps StepType -> handler
    # Handler can be:
    # - [string]      : PowerShell function name
    # - [scriptblock] : executable handler (useful for tests / hosts)
    if (-not $Registry.ContainsKey($StepType)) {
        return $null
    }

    $handler = $Registry[$StepType]
    if ($null -eq $handler) {
        return $null
    }

    if ($handler -is [scriptblock]) {
        return $handler
    }

    if ($handler -is [string]) {
        $fn = [string]$handler
        if ([string]::IsNullOrWhiteSpace($fn)) {
            return $null
        }

        # Ensure the function exists in the current session.
        $cmd = Get-Command -Name $fn -ErrorAction SilentlyContinue
        if ($null -eq $cmd) {
            return $null
        }

        return $cmd.Name
    }

    # Any other type is invalid configuration.
    throw [System.ArgumentException]::new("Invalid step handler type for '$StepType'. Allowed: string (function name) or scriptblock.", 'Registry')
}
