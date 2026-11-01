function New-IdleProviderHandle {
    <#
    .SYNOPSIS
    Creates the provider handle passed to step handlers as -Provider.

    .DESCRIPTION
    The handle binds one provider from Context.Providers to a step. Step handlers call provider methods
    through it and never handle authentication themselves:

    - Invoke(MethodName, Arguments): calls the method; appends the auth session when the method declares an
      AuthSession parameter. The session is acquired via Context.AcquireAuthSession on first use and cached
      for the lifetime of the handle (one step attempt).
    - HasMethod(MethodName): the provider implements the method (optional capabilities, e.g. bulk operations).
    - HasParameter(MethodName, ParameterName): the method declares the parameter.

    The raw provider object is not exposed, so steps cannot bypass the auth logic.

    .PARAMETER Context
    Execution context (Providers, AcquireAuthSession).

    .PARAMETER Alias
    Provider alias (resolved With.Provider).

    .PARAMETER AuthSessionName
    Optional auth session routing key (With.AuthSessionName).

    .PARAMETER AuthSessionOptions
    Optional data-only auth session options (With.AuthSessionOptions).

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.ProviderHandle)
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AuthSessionOptions', Justification = 'Used by the Invoke script method via closure.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Alias,

        [Parameter()]
        [AllowNull()]
        [string] $AuthSessionName,

        [Parameter()]
        [AllowNull()]
        [hashtable] $AuthSessionOptions
    )

    $providers = $Context.Providers
    $provider = $null
    if ($providers -is [System.Collections.IDictionary]) {
        if ($providers.Contains($Alias)) { $provider = $providers[$Alias] }
    }
    elseif ($null -ne $providers -and $null -ne $providers.PSObject.Properties[$Alias]) {
        $provider = $providers.$Alias
    }

    if ($null -eq $provider) {
        throw [System.InvalidOperationException]::new(
            "ProviderNotSupplied: Provider '$Alias' was not supplied by the host. Pass it in Providers['$Alias'] or set With.Provider to a supplied alias."
        )
    }

    # Providers that expose an EventSink property emit diagnostics events through the run's event sink
    # (e.g. IdLE.Provider.ExchangeOnline.*). Steps no longer see the raw provider, so the engine wires it.
    # Indexer lookups: member enumeration (.Properties.Name) fails under StrictMode for objects without properties.
    if ($null -ne $provider.PSObject.Properties['EventSink'] -and $null -ne $Context.PSObject.Properties['EventSink']) {
        $provider.EventSink = $Context.EventSink
    }

    # Capture command references once: script methods created with GetNewClosure() cannot resolve
    # private module functions by name.
    $testParameterCmd = Get-Command -Name 'Test-IdleProviderMethodParameter' -CommandType Function -ErrorAction Stop
    $sessionState = @{ Acquired = $false; Session = $null }
    $hasSessionName = -not [string]::IsNullOrWhiteSpace($AuthSessionName)

    $handle = [pscustomobject]@{
        PSTypeName = 'IdLE.ProviderHandle'
        Alias      = $Alias
    }

    $hasMethod = {
        param([string] $MethodName)
        return $null -ne $provider.PSObject.Methods[$MethodName]
    }.GetNewClosure()

    $hasParameter = {
        param([string] $MethodName, [string] $ParameterName)
        $method = $provider.PSObject.Methods[$MethodName]
        if ($null -eq $method) { return $false }
        return [bool](& $testParameterCmd -ProviderMethod $method -ParameterName $ParameterName)
    }.GetNewClosure()

    $invoke = {
        param([string] $MethodName, [object[]] $Arguments)

        $method = $provider.PSObject.Methods[$MethodName]
        if ($null -eq $method) {
            throw [System.InvalidOperationException]::new(
                "ProviderMethodNotImplemented: Provider '$Alias' does not implement method '$MethodName'."
            )
        }

        # [object[]] keeps a single argument an array (an if-expression would unroll it to a scalar).
        [object[]] $callArguments = @()
        if ($null -ne $Arguments) { $callArguments = @($Arguments) }
        $supportsAuthSession = [bool](& $testParameterCmd -ProviderMethod $method -ParameterName 'AuthSession')
        $canAcquire = $null -ne $Context.PSObject.Methods['AcquireAuthSession']

        if (-not $sessionState.Acquired -and ($hasSessionName -or ($supportsAuthSession -and $canAcquire))) {
            if (-not $canAcquire) {
                throw [System.InvalidOperationException]::new(
                    "With.AuthSessionName is set to '$AuthSessionName' but the execution context cannot acquire auth sessions."
                )
            }

            if ($hasSessionName) {
                $sessionState.Session = $Context.AcquireAuthSession($AuthSessionName, $AuthSessionOptions)
            }
            else {
                # An empty name requests the broker's default session.
                $sessionState.Session = $Context.AcquireAuthSession('', $null)
            }
            $sessionState.Acquired = $true
        }

        if ($supportsAuthSession) {
            # Arguments are the method's parameters without AuthSession; insert the session at its declared
            # position (e.g. ListEntitlements(IdentityKey, AuthSession, Kind)). Compiled methods expose no
            # parameter order, so the session is appended for them.
            $position = $callArguments.Count
            if ($method.MemberType -eq 'ScriptMethod' -and $null -ne $method.Script.Ast.ParamBlock) {
                $names = @($method.Script.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                $declared = [array]::IndexOf($names, 'AuthSession')
                if ($declared -ge 0 -and $declared -lt $position) { $position = $declared }
            }

            if ($null -ne $sessionState.Session -or $position -lt $callArguments.Count) {
                $withSession = [System.Collections.Generic.List[object]]::new()
                for ($index = 0; $index -lt $callArguments.Count; $index++) {
                    if ($index -eq $position) { $withSession.Add($sessionState.Session) }
                    $withSession.Add($callArguments[$index])
                }
                if ($position -ge $callArguments.Count) { $withSession.Add($sessionState.Session) }
                $callArguments = $withSession.ToArray()
            }
        }

        try {
            return $method.Invoke($callArguments)
        }
        catch [System.Management.Automation.MethodInvocationException] {
            # The handle's own Invoke is a script method that wraps again; pass on the provider's exception
            # so callers see one level of wrapping, as with direct provider calls.
            if ($null -ne $_.Exception.InnerException) { throw $_.Exception.InnerException }
            throw
        }
    }.GetNewClosure()

    $null = Add-Member -InputObject $handle -MemberType ScriptMethod -Name 'Invoke' -Value $invoke -Force
    $null = Add-Member -InputObject $handle -MemberType ScriptMethod -Name 'HasMethod' -Value $hasMethod -Force
    $null = Add-Member -InputObject $handle -MemberType ScriptMethod -Name 'HasParameter' -Value $hasParameter -Force

    return $handle
}
