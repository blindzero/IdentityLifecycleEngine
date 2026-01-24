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
    A hashtable that maps session configurations to credentials. Each key is a hashtable
    representing the AuthSessionOptions pattern, and each value is the PSCredential to return.

    Common patterns:
    - @{ Role = 'Tier0' } -> $tier0Credential
    - @{ Role = 'Admin' } -> $adminCredential
    - @{ Domain = 'SourceAD' } -> $sourceCred
    - @{ Environment = 'Production' } -> $prodCred

    .PARAMETER DefaultCredential
    Optional default credential to return when no session options are provided or
    when the options don't match any entry in SessionMap.

    .EXAMPLE
    # Simple role-based broker
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Credential
        @{ Role = 'Admin' } = $adminCredential
    } -DefaultCredential $adminCredential

    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = New-IdleADIdentityProvider
        AuthSessionBroker = $broker
    }

    .EXAMPLE
    # Domain-based broker for multi-forest scenarios
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Domain = 'SourceAD' } = $sourceCred
        @{ Domain = 'TargetAD' } = $targetCred
    }

    .OUTPUTS
    PSCustomObject with AcquireAuthSession method
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $SessionMap,

        [Parameter()]
        [AllowNull()]
        [PSCredential] $DefaultCredential
    )

    $broker = [pscustomobject]@{
        PSTypeName = 'IdLE.AuthSessionBroker'
        SessionMap = $SessionMap
        DefaultCredential = $DefaultCredential
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

        # $Name is part of the broker contract but not used in this simple implementation
        # This broker routes based on Options only; custom brokers may use Name for additional routing
        $null = $Name

        # If no options provided, return default
        if ($null -eq $Options -or $Options.Count -eq 0) {
            if ($null -ne $this.DefaultCredential) {
                return $this.DefaultCredential
            }
            throw "No auth session options provided and no default credential configured."
        }

        # Find matching session in map
        foreach ($entry in $this.SessionMap.GetEnumerator()) {
            $pattern = $entry.Key
            $credential = $entry.Value

            # Check if all keys in pattern match Options
            $matches = $true
            foreach ($key in $pattern.Keys) {
                if (-not $Options.ContainsKey($key) -or $Options[$key] -ne $pattern[$key]) {
                    $matches = $false
                    break
                }
            }

            if ($matches) {
                return $credential
            }
        }

        # No match found
        if ($null -ne $this.DefaultCredential) {
            return $this.DefaultCredential
        }

        $optionsStr = ($Options.Keys | ForEach-Object { "$_=$($Options[$_])" }) -join ', '
        throw "No matching credential found for options: $optionsStr"
    } -Force

    return $broker
}
