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
            Entitlements = @(
                @{ Kind = 'Group'; Id = 'demo-group'; DisplayName = 'Demo Group' }
            )
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

    function ConvertTo-IdleMockEntitlement {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Value
        )

        $kind = $null
        $id = $null
        $displayName = $null

        if ($Value -is [System.Collections.IDictionary]) {
            $kind = $Value['Kind']
            $id = $Value['Id']
            if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
        }
        else {
            $props = $Value.PSObject.Properties
            if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
            if ($props.Name -contains 'Id') { $id = $Value.Id }
            if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
        }

        if ([string]::IsNullOrWhiteSpace([string]$kind)) {
            throw "Entitlement.Kind must not be empty."
        }
        if ([string]::IsNullOrWhiteSpace([string]$id)) {
            throw "Entitlement.Id must not be empty."
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Entitlement'
            Kind        = [string]$kind
            Id          = [string]$id
            DisplayName = if ($null -eq $displayName -or [string]::IsNullOrWhiteSpace([string]$displayName)) {
                $null
            }
            else {
                [string]$displayName
            }
        }
    }

    function Test-IdleMockEntitlementEquals {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $A,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $B
        )

        $aEnt = ConvertTo-IdleMockEntitlement -Value $A
        $bEnt = ConvertTo-IdleMockEntitlement -Value $B

        if ($aEnt.Kind -ne $bEnt.Kind) {
            return $false
        }

        return [string]::Equals($aEnt.Id, $bEnt.Id, [System.StringComparison]::OrdinalIgnoreCase)
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
            'IdLE.Entitlement.List'
            'IdLE.Entitlement.Grant'
            'IdLE.Entitlement.Revoke'
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
                IdentityKey  = $IdentityKey
                Enabled      = $true
                Attributes   = @{}
                Entitlements = @()
            }
        }

        $raw = $this.Store[$IdentityKey]

        if ($null -eq $raw.Entitlements) {
            $raw.Entitlements = @()
        }

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
                IdentityKey  = $IdentityKey
                Enabled      = $true
                Attributes   = @{}
                Entitlements = @()
            }
        }

        $identity = $this.Store[$IdentityKey]

        if ($null -eq $identity.Attributes) {
            $identity.Attributes = @{}
        }
        if ($null -eq $identity.Entitlements) {
            $identity.Entitlements = @()
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
                IdentityKey  = $IdentityKey
                Enabled      = $true
                Attributes   = @{}
                Entitlements = @()
            }
        }

        $identity = $this.Store[$IdentityKey]
        if ($null -eq $identity.Entitlements) {
            $identity.Entitlements = @()
        }

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

    $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        if (-not $this.Store.ContainsKey($IdentityKey)) {
            throw "Identity '$IdentityKey' does not exist in the mock provider store."
        }

        $identity = $this.Store[$IdentityKey]
        if ($null -eq $identity.Entitlements) {
            $identity.Entitlements = @()
        }

        $result = @()
        foreach ($e in @($identity.Entitlements)) {
            $normalized = ConvertTo-IdleMockEntitlement -Value $e
            $result += $normalized
        }

        return $result
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GrantEntitlement -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Entitlement
        )

        if (-not $this.Store.ContainsKey($IdentityKey)) {
            throw "Identity '$IdentityKey' does not exist in the mock provider store."
        }

        $normalized = ConvertTo-IdleMockEntitlement -Value $Entitlement

        $identity = $this.Store[$IdentityKey]
        if ($null -eq $identity.Entitlements) {
            $identity.Entitlements = @()
        }

        $existing = $identity.Entitlements | Where-Object { Test-IdleMockEntitlementEquals -A $_ -B $normalized }

        $changed = $false
        if (@($existing).Count -eq 0) {
            $identity.Entitlements += $normalized
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'GrantEntitlement'
            IdentityKey = $IdentityKey
            Changed     = [bool]$changed
            Entitlement = $normalized
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name RevokeEntitlement -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Entitlement
        )

        if (-not $this.Store.ContainsKey($IdentityKey)) {
            throw "Identity '$IdentityKey' does not exist in the mock provider store."
        }

        $normalized = ConvertTo-IdleMockEntitlement -Value $Entitlement

        $identity = $this.Store[$IdentityKey]
        if ($null -eq $identity.Entitlements) {
            $identity.Entitlements = @()
        }

        $remaining = @()
        $removed = $false

        foreach ($item in @($identity.Entitlements)) {
            if (Test-IdleMockEntitlementEquals -A $item -B $normalized) {
                $removed = $true
                continue
            }

            $remaining += $item
        }

        $identity.Entitlements = $remaining

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'RevokeEntitlement'
            IdentityKey = $IdentityKey
            Changed     = [bool]$removed
            Entitlement = $normalized
        }
    } -Force

    return $provider
}
