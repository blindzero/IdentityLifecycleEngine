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
    The value can be a PSCredential, token string, session object, or any object appropriate
    for the AuthSessionType.

    Keys can include AuthSessionName for name-based routing:
    - @{ AuthSessionName = 'AD'; Role = 'ADAdm' } -> $admAD (AuthSessionName + Role routing)
    - @{ AuthSessionName = 'EXO' } -> $exoToken (AuthSessionName-only routing)
    - @{ Role = 'Tier0' } -> $tier0Credential (Options-only routing, legacy support)

    SessionMap is optional if DefaultAuthSession is provided.

    .PARAMETER DefaultAuthSession
    Optional default auth session to return when no session options are provided or
    when the options don't match any entry in SessionMap. Can be a PSCredential, token
    string, session object, or any object appropriate for the AuthSessionType.

    .PARAMETER AuthSessionType
    Specifies the type of authentication session. This determines validation rules,
    lifecycle management, and telemetry behavior.

    Valid values:
    - 'OAuth': Token-based authentication (e.g., Microsoft Graph, Exchange Online)
    - 'PSRemoting': PowerShell remoting execution context (e.g., Entra Connect)
    - 'Credential': Credential-based authentication (e.g., Active Directory, mock providers)

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
        @{ AuthSessionName = 'EXO'; Role = 'EXOAdm' } = $exoToken
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

        [Parameter(Mandatory)]
        [ValidateSet('OAuth', 'PSRemoting', 'Credential')]
        [string] $AuthSessionType
    )

    # Validate: If SessionMap is empty/null, DefaultAuthSession must be provided
    if (($null -eq $SessionMap -or $SessionMap.Count -eq 0) -and $null -eq $DefaultAuthSession) {
        throw "SessionMap is empty or null. DefaultAuthSession must be provided when SessionMap is not used."
    }

    $broker = [pscustomobject]@{
        PSTypeName = 'IdLE.AuthSessionBroker'
        SessionMap = $SessionMap
        DefaultAuthSession = $DefaultAuthSession
        AuthSessionType = $AuthSessionType
    }

    $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [AllowNull()]
            [hashtable] $Options
        )

        # TODO: Implement type-specific validation rules for AuthSessionType
        # Current implementation allows all options for all session types
        # Future enhancements may add:
        # - OAuth: Validate token format, expiration, scopes
        # - PSRemoting: Validate remote session state, connectivity
        # - Credential: Validate credential format, domain membership

        # If SessionMap is null or empty, return default
        if ($null -eq $this.SessionMap -or $this.SessionMap.Count -eq 0) {
            if ($null -ne $this.DefaultAuthSession) {
                return $this.DefaultAuthSession
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
                
                # If pattern has ONLY AuthSessionName (no other keys), it's a match
                if ($pattern.Keys.Count -eq 1) {
                    $authSessionNameMatches += $entry
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
            return $matchingEntries[0].Value
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
            return $this.DefaultAuthSession
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
