function Resolve-IdleStepHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepType,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $StepRegistry
    )

    $handlerName = $null

    if ($StepRegistry -is [System.Collections.IDictionary]) {
        if ($StepRegistry.Contains($StepType)) {
            $handlerName = $StepRegistry[$StepType]
        }
    }
    else {
        if ($StepRegistry.PSObject.Properties.Name -contains $StepType) {
            $handlerName = $StepRegistry.$StepType
        }
    }

    if ($null -eq $handlerName -or [string]::IsNullOrWhiteSpace([string]$handlerName)) {
        throw [System.ArgumentException]::new("No step handler registered for step type '$StepType'.", 'Providers')
    }

    # Reject ScriptBlock handlers (secure default).
    if ($handlerName -is [scriptblock]) {
        throw [System.ArgumentException]::new(
            "Step registry handler for '$StepType' must be a function name (string), not a ScriptBlock.",
            'Providers'
        )
    }

    # Resolve the handler command.
    # The handler name can be:
    # 1) A simple function name (e.g. "Invoke-IdleStepEmitEvent") - globally available
    # 2) A module-qualified name (e.g. "IdLE.Steps.Common\Invoke-IdleStepEmitEvent") - from a nested module
    #
    # Module-qualified names are used for built-in steps that are loaded as nested modules
    # and not exported globally to keep the session clean.

    $cmd = $null

    # Try simple lookup first (globally available commands)
    $cmd = Get-Command -Name ([string]$handlerName) -CommandType Function -ErrorAction SilentlyContinue

    # If not found and name contains backslash, try module-qualified lookup
    if ($null -eq $cmd -and ([string]$handlerName).Contains('\')) {
        $parts = ([string]$handlerName).Split('\', 2)
        if ($parts.Count -eq 2) {
            $moduleName = $parts[0]
            $commandName = $parts[1]

            # Get-Module -All returns loaded modules (including nested/hidden modules)
            # We use -All to find modules that are loaded but not in the global session state
            $modules = @(Get-Module -Name $moduleName -All)
            if ($modules.Count -gt 0) {
                $module = $modules[0]
                if ($null -ne $module.ExportedCommands -and $module.ExportedCommands.ContainsKey($commandName)) {
                    $cmd = $module.ExportedCommands[$commandName]
                }
            }
        }
    }

    if ($null -eq $cmd) {
        throw [System.ArgumentException]::new("Step handler '$handlerName' for step type '$StepType' could not be resolved to a valid command.", 'Providers')
    }

    return $cmd
}
