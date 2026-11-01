function New-IdleStepHandlerArguments {
    <#
    .SYNOPSIS
    Builds the parameters for invoking a step handler and checks the handler signature.

    .DESCRIPTION
    Step handler contract (see docs/extend/steps.md):
    - -With (always; validated With without the common keys).
    - -Context (execution context) if the handler declares it.
    - -Provider (provider handle) if and only if the step declares a Provider. Steps that declare a Provider
      carry With.Provider after planning (default applied from Provider.DefaultAlias).
    - -Step (optional): read-only step metadata (Name, Type).

    Handler signature errors start with LegacyStepHandler or InvalidStepHandlerSignature.

    .PARAMETER Handler
    Resolved handler command.

    .PARAMETER Step
    Plan step (Name, Type, With).

    .PARAMETER Context
    Execution context.

    .OUTPUTS
    System.Collections.Hashtable (splattable parameters).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $Handler,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context
    )

    $stepName = [string](Get-IdlePropertyValue -Object $Step -Name 'Name')
    $stepType = [string](Get-IdlePropertyValue -Object $Step -Name 'Type')
    $stepWith = Get-IdlePropertyValue -Object $Step -Name 'With'
    if ($null -eq $stepWith) { $stepWith = @{} }

    $commonKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
    $usesProvider = $stepWith -is [System.Collections.IDictionary] -and $stepWith.Contains('Provider')

    $parameters = $Handler.Parameters
    $handlerLabel = "Step handler '$($Handler.Name)' for step type '$stepType'"

    if (-not $parameters.ContainsKey('With')) {
        throw [System.InvalidOperationException]::new(
            "LegacyStepHandler: $handlerLabel uses the pre-1.0 handler contract (no -With parameter). Handlers declare -With (plus -Context, -Provider and -Step as needed) and return `$null or @{ Changed; Data; State }. See docs/extend/steps.md."
        )
    }

    if ($usesProvider -and -not $parameters.ContainsKey('Provider')) {
        throw [System.InvalidOperationException]::new(
            "InvalidStepHandlerSignature: $handlerLabel must declare a -Provider parameter because the step metadata declares a Provider."
        )
    }

    if (-not $usesProvider -and $parameters.ContainsKey('Provider')) {
        throw [System.InvalidOperationException]::new(
            "InvalidStepHandlerSignature: $handlerLabel declares -Provider, but the step metadata declares no Provider. Add Provider = @{ DefaultAlias = '<alias>' } to the metadata or remove the parameter."
        )
    }

    # The handler sees only its domain keys; provider routing and authentication are engine concerns.
    $handlerWith = @{}
    foreach ($key in @($stepWith.PSBase.Keys)) {
        if ($usesProvider -and $commonKeys -contains [string]$key) { continue }
        $handlerWith[[string]$key] = $stepWith[$key]
    }

    $arguments = @{ With = $handlerWith }

    if ($parameters.ContainsKey('Context')) {
        $arguments.Context = $Context
    }

    if ($usesProvider) {
        $authSessionOptions = if ($stepWith.Contains('AuthSessionOptions')) { $stepWith['AuthSessionOptions'] } else { $null }
        $arguments.Provider = New-IdleProviderHandle `
            -Context $Context `
            -Alias ([string]$stepWith['Provider']) `
            -AuthSessionName $(if ($stepWith.Contains('AuthSessionName')) { [string]$stepWith['AuthSessionName'] } else { $null }) `
            -AuthSessionOptions $authSessionOptions
    }

    if ($parameters.ContainsKey('Step')) {
        $arguments.Step = [pscustomobject]@{
            PSTypeName = 'IdLE.StepInfo'
            Name       = $stepName
            Type       = $stepType
        }
    }

    return $arguments
}
