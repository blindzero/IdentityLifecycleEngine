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
    $provider.GetIdentity('user1') | Format-List

    .EXAMPLE
    $provider = New-IdleMockIdentityProvider -InitialStore @{
        'user1' = @{
            IdentityKey = 'user1'
            Enabled     = $true
            Attributes  = @{
                Department = 'IT'
            }
        }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $InitialStore
    )

    $store = @{}

    if ($null -ne $InitialStore) {
        foreach ($key in $InitialStore.Keys) {
            $store[$key] = $InitialStore[$key]
        }
    }

    $provider = [pscustomobject]@{
        PSTypeName = 'IdLE.Provider.MockIdentityProvider'
        Name       = 'MockIdentityProvider'
        Store      = $store
    }

    $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
        <#
        .SYNOPSIS
        Advertises the capabilities provided by this provider instance.

        .DESCRIPTION
        Capabilities are stable string identifiers used by IdLE to validate that
        a workflow plan can be executed with the available providers.

        This mock provider intentionally advertises only the capabilities that it
        implements to keep tests deterministic.
        #>

        return @(
            'Identity.Read'
            'Identity.Attribute.Ensure'
            'Identity.Disable'
        )
    } -Force

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

        $raw = $this.Store[$IdentityKey]

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Identity'
            IdentityKey = $raw.IdentityKey
            Enabled     = [bool]$raw.Enabled
            Attributes  = [hashtable]$raw.Attributes
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [AllowNull()]
            [object] $Value
        )

        if (-not $this.Store.ContainsKey($IdentityKey)) {
            $this.Store[$IdentityKey] = @{
                IdentityKey = $IdentityKey
                Enabled     = $true
                Attributes  = @{}
            }
        }

        $identity = $this.Store[$IdentityKey]

        if ($null -eq $identity.Attributes) {
            $identity.Attributes = @{}
        }

        $changed = $false

        if (-not $identity.Attributes.ContainsKey($Name)) {
            $changed = $true
            $identity.Attributes[$Name] = $Value
        }
        else {
            $existing = $identity.Attributes[$Name]

            # Compare loosely because values may come in as different but equivalent types in tests.
            if ($existing -ne $Value) {
                $changed = $true
                $identity.Attributes[$Name] = $Value
            }
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnsureAttribute'
            IdentityKey = $IdentityKey
            Changed     = [bool]$changed
            Name        = $Name
            Value       = $Value
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        if (-not $this.Store.ContainsKey($IdentityKey)) {
            $this.Store[$IdentityKey] = @{
                IdentityKey = $IdentityKey
                Enabled     = $true
                Attributes  = @{}
            }
        }

        $identity = $this.Store[$IdentityKey]
        $changed = $false

        if ($identity.Enabled -ne $false) {
            $changed = $true
        }

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
