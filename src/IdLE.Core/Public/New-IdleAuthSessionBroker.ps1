function New-IdleAuthSessionBroker {
    <#
    .SYNOPSIS
    Creates a simple AuthSessionBroker for use with IdLE providers.

    .DESCRIPTION
    Creates an AuthSessionBroker that routes authentication based on user-defined options.
    The broker is used by steps to acquire credentials at runtime without embedding
    secrets in workflows or provider construction.

    This is a convenience function for common scenarios. For advanced scenarios
    (vault integration, MFA, etc.), implement a custom broker object with an
    AcquireAuthSession method.

    .PARAMETER SessionMap
    Optional hashtable that maps session configurations to auth sessions. Each key is a hashtable
    representing the AuthSessionOptions pattern, and each value is the auth session to return.

    Values can be specified in two formats:

    1. Legacy/Untyped (requires -AuthSessionType):
       - Direct session object: @{ Role = 'Admin' } = $credential

    2. Typed (supports mixed types, -AuthSessionType acts as default):
       - Hashtable: @{ Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $credential }
       - PSCustomObject: @{ Role = 'Admin' } = [pscustomobject]@{ AuthSessionType = 'OAuth'; Session = $token }

    Keys can include AuthSessionName for name-based routing:
    - @{ AuthSessionName = 'AD'; Role = 'ADAdm' } -> $admAD (AuthSessionName + Role routing)
    - @{ AuthSessionName = 'EXO' } -> $exoToken (AuthSessionName-only routing)
    - @{ Role = 'Tier0' } -> $tier0Credential (Options-only routing, legacy support)
    - @{ Server = 'AADConnect01' } -> $remoteSession (for PSRemoting scenarios)
    - @{ Domain = 'SourceAD' } -> $sourceCred (for multi-forest scenarios)
    - @{ Environment = 'Production' } -> $prodCred (for environment-specific routing)

    SessionMap is optional if DefaultAuthSession is provided.

    .PARAMETER DefaultAuthSession
    Optional default auth session to return when no session options are provided or
    when the options don't match any entry in SessionMap.

    Can be specified in two formats:
    1. Legacy/Untyped (requires -AuthSessionType): $credential
    2. Typed: @{ AuthSessionType = 'Credential'; Session = $credential }

    At least one of SessionMap or DefaultAuthSession must be provided.

    .PARAMETER AuthSessionType
    Optional default authentication session type. Acts as the default for untyped
    SessionMap entries and DefaultAuthSession. This determines validation rules,
    lifecycle management, and telemetry behavior.

    Valid values:
    - 'OAuth': Token-based authentication (e.g., Microsoft Graph, Exchange Online)
    - 'PSRemoting': PowerShell remoting execution context (e.g., Entra Connect)
    - 'Credential': Credential-based authentication (e.g., Active Directory, mock providers)

    If not provided, all SessionMap values and DefaultAuthSession must be typed
    (include AuthSessionType and Session properties).

    .EXAMPLE
    # Simple single-credential broker (no SessionMap required)
    $broker = New-IdleAuthSessionBroker -DefaultAuthSession $admCred -AuthSessionType 'Credential'

    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = New-IdleADIdentityProvider
        AuthSessionBroker = $broker
    }

    .EXAMPLE
    # AuthSessionName-based routing with roles
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ AuthSessionName = 'AD'; Role = 'ADAdm' } = $tier0Credential
        @{ AuthSessionName = 'AD'; Role = 'ADRead' } = $readOnlyCredential
    } -DefaultAuthSession $adminCredential -AuthSessionType 'Credential'

    .EXAMPLE
    # OAuth broker with token strings
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Admin' } = $graphToken
    } -DefaultAuthSession $graphToken -AuthSessionType 'OAuth'

    .EXAMPLE
    # Domain-based broker for multi-forest scenarios with Credential session type
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Domain = 'SourceAD' } = $sourceCred
        @{ Domain = 'TargetAD' } = $targetCred
    } -AuthSessionType 'Credential'

    .EXAMPLE
    # PSRemoting broker for Entra Connect directory sync
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Server = 'AADConnect01' } = $remoteSessionCred
    } -AuthSessionType 'PSRemoting'

    .EXAMPLE
    # Environment-based routing for multi-environment scenarios
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Environment = 'Production' } = $prodCred
        @{ Environment = 'Test' } = $testCred
    } -DefaultAuthSession $devCred -AuthSessionType 'Credential'

    .EXAMPLE
    # Mixed-type broker for AD (Credential) + EXO (OAuth) in single workflow
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
        @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
    }

    .EXAMPLE
    # Mixed typed and untyped with default AuthSessionType
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ AuthSessionName = 'AD' } = $adCred  # Uses default 'Credential'
        @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
    } -AuthSessionType 'Credential'

    .OUTPUTS
    PSCustomObject with AcquireAuthSession method
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [hashtable] $SessionMap,

        [Parameter()]
        [AllowNull()]
        [object] $DefaultAuthSession,

        [Parameter()]
        [ValidateSet('OAuth', 'PSRemoting', 'Credential')]
        [string] $AuthSessionType
    )

    # Validate: If SessionMap is empty/null, DefaultAuthSession must be provided
    if (($null -eq $SessionMap -or $SessionMap.Count -eq 0) -and $null -eq $DefaultAuthSession) {
        throw "SessionMap is empty or null. DefaultAuthSession must be provided when SessionMap is not used."
    }

    # Helper function to detect if a value is a typed session descriptor
    $isTypedSession = {
        param($value)

        if ($null -eq $value) {
            return $false
        }

        # Check for hashtable with AuthSessionType and Session keys
        if ($value -is [hashtable]) {
            return ($value.ContainsKey('AuthSessionType') -and $value.ContainsKey('Session'))
        }

        # Check for PSCustomObject with AuthSessionType and Session properties
        if ($value -is [pscustomobject]) {
            $properties = $value.PSObject.Properties.Name
            return (($properties -contains 'AuthSessionType') -and ($properties -contains 'Session'))
        }

        return $false
    }

    # Helper function to normalize session value to internal format
    $normalizeSessionValue = {
        param($value, $defaultType, $context)

        if ($null -eq $value) {
            return $null
        }

        # Check if value is already typed
        if (& $isTypedSession $value) {
            $sessionType = $value.AuthSessionType
            $session = $value.Session

            # Validate the provided AuthSessionType
            if ($sessionType -notin @('OAuth', 'PSRemoting', 'Credential')) {
                throw "Invalid AuthSessionType '$sessionType' in $context. Valid values: 'OAuth', 'PSRemoting', 'Credential'."
            }

            return @{
                AuthSessionType = $sessionType
                Session = $session
            }
        }

        # Untyped value - use default type
        if ([string]::IsNullOrEmpty($defaultType)) {
            throw "Untyped session value found in $context, but no default -AuthSessionType provided. Either provide -AuthSessionType or use typed session values: @{ AuthSessionType = '<type>'; Session = <value> }"
        }

        return @{
            AuthSessionType = $defaultType
            Session = $value
        }
    }

    # Normalize SessionMap entries
    $normalizedSessionMap = @{}
    if ($null -ne $SessionMap -and $SessionMap.Count -gt 0) {
        foreach ($entry in $SessionMap.GetEnumerator()) {
            $pattern = $entry.Key
            $value = $entry.Value

            # Create a readable pattern description for error messages
            $patternDesc = ($pattern.Keys | ForEach-Object { "$_=$($pattern[$_])" }) -join ', '
            $context = "SessionMap entry { $patternDesc }"

            $normalizedValue = & $normalizeSessionValue $value $AuthSessionType $context
            $normalizedSessionMap[$pattern] = $normalizedValue
        }
    }

    # Normalize DefaultAuthSession
    $normalizedDefaultAuthSession = $null
    if ($null -ne $DefaultAuthSession) {
        $normalizedDefaultAuthSession = & $normalizeSessionValue $DefaultAuthSession $AuthSessionType 'DefaultAuthSession'
    }

    $broker = [pscustomobject]@{
        PSTypeName = 'IdLE.AuthSessionBroker'
        SessionMap = $normalizedSessionMap
        DefaultAuthSession = $normalizedDefaultAuthSession
        AuthSessionType = $AuthSessionType  # Store for backward compatibility
    }

    $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Name,

            [Parameter()]
            [AllowNull()]
            [hashtable] $Options
        )

        # Empty string signals default session request
        if ([string]::IsNullOrEmpty($Name)) {
            if ($null -ne $this.DefaultAuthSession) {
                $normalized = $this.DefaultAuthSession

                # Validate type before returning
                $validationScript = (Get-Command -Name 'Assert-IdleAuthSessionMatchesType' -ErrorAction Stop).ScriptBlock
                & $validationScript -AuthSessionType $normalized.AuthSessionType -Session $normalized.Session -SessionName '<default>'

                return $normalized.Session
            }
            throw "No default auth session configured."
        }

        # If SessionMap is null or empty, return default
        if ($null -eq $this.SessionMap -or $this.SessionMap.Count -eq 0) {
            if ($null -ne $this.DefaultAuthSession) {
                $normalized = $this.DefaultAuthSession

                # Validate type before returning
                $validationScript = (Get-Command -Name 'Assert-IdleAuthSessionMatchesType' -ErrorAction Stop).ScriptBlock
                & $validationScript -AuthSessionType $normalized.AuthSessionType -Session $normalized.Session -SessionName $Name

                return $normalized.Session
            }
            throw "No SessionMap configured and no default auth session available."
        }

        # Matching logic:
        # 1. If Name provided: try to match entries with AuthSessionName key
        # 2. If Options provided: match all key/value pairs
        # 3. Fall back to DefaultAuthSession
        # 4. Fail with clear error

        $authSessionNameMatches = @()
        $legacyMatches = @()
        
        foreach ($entry in $this.SessionMap.GetEnumerator()) {
            $pattern = $entry.Key
            
            # Check if pattern includes AuthSessionName
            if ($pattern.ContainsKey('AuthSessionName')) {
                # AuthSessionName must match
                if ($pattern.AuthSessionName -ne $Name) {
                    continue
                }
                
                # If pattern has ONLY AuthSessionName (no other keys)
                if ($pattern.Keys.Count -eq 1) {
                    # Only match if Options is null or empty
                    if ($null -eq $Options -or $Options.Count -eq 0) {
                        $authSessionNameMatches += $entry
                    }
                    continue
                }
                
                # Pattern has additional keys beyond AuthSessionName
                # All other keys in pattern must match Options (if Options provided)
                $matches = $true
                foreach ($key in $pattern.Keys) {
                    if ($key -eq 'AuthSessionName') {
                        continue  # Already checked
                    }
                    
                    # If Options is null or doesn't contain the key, no match
                    if ($null -eq $Options -or -not $Options.ContainsKey($key) -or $Options[$key] -ne $pattern[$key]) {
                        $matches = $false
                        break
                    }
                }
                
                if ($matches) {
                    $authSessionNameMatches += $entry
                }
            }
            else {
                # Legacy: pattern without AuthSessionName - match based on Options only
                if ($null -eq $Options -or $Options.Count -eq 0) {
                    continue  # No options to match
                }
                
                $matches = $true
                foreach ($key in $pattern.Keys) {
                    if (-not $Options.ContainsKey($key) -or $Options[$key] -ne $pattern[$key]) {
                        $matches = $false
                        break
                    }
                }
                
                if ($matches) {
                    $legacyMatches += $entry
                }
            }
        }

        # Prioritize AuthSessionName-based matches over legacy matches
        $matchingEntries = @()
        if (@($authSessionNameMatches).Count -gt 0) {
            $matchingEntries = @($authSessionNameMatches)
        } else {
            $matchingEntries = @($legacyMatches)
        }

        # Return first match if exactly one found
        if ($matchingEntries.Count -eq 1) {
            $normalized = $matchingEntries[0].Value

            # Validate type before returning
            $validationScript = (Get-Command -Name 'Assert-IdleAuthSessionMatchesType' -ErrorAction Stop).ScriptBlock
            & $validationScript -AuthSessionType $normalized.AuthSessionType -Session $normalized.Session -SessionName $Name

            return $normalized.Session
        }
        
        # If multiple matches, this is ambiguous - fail with clear error
        if ($matchingEntries.Count -gt 1) {
            $matchDetails = ($matchingEntries | ForEach-Object {
                $currentEntry = $_
                $keyStr = ($currentEntry.Key.Keys | ForEach-Object { "$_=$($currentEntry.Key[$_])" }) -join ', '
                "{ $keyStr }"
            }) -join '; '
            throw "Ambiguous auth session match for Name='$Name'. Multiple entries matched: $matchDetails. Provide AuthSessionOptions to disambiguate."
        }

        # No match found - fall back to default
        if ($null -ne $this.DefaultAuthSession) {
            $normalized = $this.DefaultAuthSession

            # Validate type before returning
            $validationScript = (Get-Command -Name 'Assert-IdleAuthSessionMatchesType' -ErrorAction Stop).ScriptBlock
            & $validationScript -AuthSessionType $normalized.AuthSessionType -Session $normalized.Session -SessionName $Name

            return $normalized.Session
        }

        # No match and no default
        $nameStr = "Name='$Name'"
        $optionsPart = if ($null -ne $Options -and $Options.Count -gt 0) {
            $optsStr = ($Options.Keys | ForEach-Object { "$_=$($Options[$_])" }) -join ', '
            ", Options={ $optsStr }"
        } else {
            ""
        }
        throw "No matching auth session found for $nameStr$optionsPart and no default auth session configured."
    } -Force

    return $broker
}
