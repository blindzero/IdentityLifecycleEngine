function New-IdleMockIdentityProvider {
    <#
    .SYNOPSIS
    Creates an in-memory identity provider for tests and demos.

    .DESCRIPTION
    This provider is deterministic and has no external dependencies.
    It is designed to be used in unit tests, contract tests, and example workflows.

    The provider keeps all state in a private in-memory store that is scoped to the
    returned provider object instance (no global state). This makes tests predictable.

    .PARAMETER InitialStore
    Optional initial store content. This is useful when a test wants to start with
    pre-seeded identities. The input is shallow-copied to avoid unintended mutations
    from the outside.

    .EXAMPLE
    $provider = New-IdleMockIdentityProvider
    $provider.EnsureAttribute('user1', 'Department', 'IT') | Out-Null

    .EXAMPLE
    $provider = New-IdleMockIdentityProvider -InitialStore @{
        'user1' = @{
            IdentityKey = 'user1'
            Enabled     = $true
            Attributes  = @{ Department = 'HR' }
        }
    }

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.Provider.MockIdentityProvider)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $InitialStore = @{}
    )

    # Shallow-copy the initial store to keep the provider instance deterministic.
    # We avoid referencing external hashtables directly, so tests cannot mutate the provider by accident.
    $store = @{}
    foreach ($key in $InitialStore.Keys) {
        $store[$key] = $InitialStore[$key]
    }

    $provider = [pscustomobject]@{
        PSTypeName = 'IdLE.Provider.MockIdentityProvider'
        Name       = 'MockIdentityProvider'
        Store      = $store
    }

    $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        # Create missing identities on demand to keep tests and demos frictionless.
        if (-not $this.Store.ContainsKey($IdentityKey)) {
            $this.Store[$IdentityKey] = @{
                IdentityKey = $IdentityKey
                Enabled     = $true
                Attributes  = @{}
            }
        }

        # Ensure required sub-structures exist even when the identity was pre-seeded.
        if (-not ($this.Store[$IdentityKey] -is [hashtable])) {
            throw "Mock identity store entry '$IdentityKey' must be a hashtable."
        }
        if (-not $this.Store[$IdentityKey].ContainsKey('Attributes') -or $null -eq $this.Store[$IdentityKey].Attributes) {
            $this.Store[$IdentityKey].Attributes = @{}
        }
        if (-not ($this.Store[$IdentityKey].Attributes -is [hashtable])) {
            throw "Mock identity '$IdentityKey' property 'Attributes' must be a hashtable."
        }
        if (-not $this.Store[$IdentityKey].ContainsKey('Enabled')) {
            $this.Store[$IdentityKey].Enabled = $true
        }

        return $this.Store[$IdentityKey]
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter(Mandatory)]
            [AllowNull()]
            $Value
        )

        $identity = $this.GetIdentity($IdentityKey)
        $attrs = $identity.Attributes

        $hasCurrent = $attrs.ContainsKey($Name)
        $current = if ($hasCurrent) { $attrs[$Name] } else { $null }

        # Idempotent convergence: only change state if the desired value differs.
        $changed = (-not $hasCurrent) -or ($current -ne $Value)

        if ($changed) {
            $attrs[$Name] = $Value
        }

        return [pscustomobject]@{
            PSTypeName    = 'IdLE.ProviderResult'
            Operation     = 'EnsureAttribute'
            IdentityKey   = $IdentityKey
            Name          = $Name
            PreviousValue = $current
            Changed       = [bool]$changed
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        $identity = $this.GetIdentity($IdentityKey)

        # Idempotent convergence: if already disabled, do nothing.
        $changed = ($identity.Enabled -ne $false)
        if ($changed) {
            $identity.Enabled = $false
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'DisableIdentity'
            IdentityKey = $IdentityKey
            Changed     = [bool]$changed
        }
    } -Force

    return $provider
}
