function New-IdleADIdentityProvider {
    <#
    .SYNOPSIS
    Creates an Active Directory identity provider for IdLE.

    .DESCRIPTION
    This provider integrates with on-premises Active Directory environments.
    It requires the ActiveDirectory PowerShell module (RSAT) and runs on Windows only.

    The provider supports common identity operations (Create, Read, Disable, Enable, Move, Delete)
    and group entitlement management (List, Grant, Revoke).

    Identity addressing supports:
    - GUID (ObjectGuid) - pattern: ^[0-9a-fA-F-]{36}$ or N-format
    - UPN (UserPrincipalName) - contains @
    - sAMAccountName - default fallback

    Authentication:
    Provider methods accept an optional AuthSession parameter for runtime credential
    selection via the AuthSessionBroker. This enables multi-role scenarios (e.g.,
    Tier0 vs. Admin) without embedding credentials in the provider or workflow.

    By default, the provider uses integrated authentication (run-as credentials).
    For runtime credential selection, configure an AuthSessionBroker and use
    With.AuthSessionName and With.AuthSessionOptions in step definitions.

    .PARAMETER AllowDelete
    Opt-in flag to enable the IdLE.Identity.Delete capability.
    When $true, the provider advertises the Delete capability and allows identity deletion.
    Default is $false for safety.

    .PARAMETER PasswordGenerationFallbackMinLength
    Fallback minimum password length when domain policy cannot be read. Default is 24.

    .PARAMETER PasswordGenerationRequireUpper
    Fallback requirement for uppercase characters in generated passwords. Default is $true.

    .PARAMETER PasswordGenerationRequireLower
    Fallback requirement for lowercase characters in generated passwords. Default is $true.

    .PARAMETER PasswordGenerationRequireDigit
    Fallback requirement for digit characters in generated passwords. Default is $true.

    .PARAMETER PasswordGenerationRequireSpecial
    Fallback requirement for special characters in generated passwords. Default is $true.

    .PARAMETER PasswordGenerationSpecialCharSet
    Set of special characters to use in generated passwords. Default is '!@#$%&*+-_=?'.

    .PARAMETER Adapter
    Internal parameter for dependency injection during testing. Allows unit tests to inject
    a fake AD adapter without requiring a real Active Directory environment.

    .EXAMPLE
    # Use integrated authentication (run-as)
    $provider = New-IdleADIdentityProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
    }

    .EXAMPLE
    # Custom password generation fallback configuration
    $provider = New-IdleADIdentityProvider -PasswordGenerationFallbackMinLength 32 -PasswordGenerationSpecialCharSet '!@#$%^&*()'
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
    }

    .EXAMPLE
    # Multi-role scenario with New-IdleAuthSessionBroker (recommended)
    $tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
    $adminCredential = Get-Credential -Message "Enter regular admin credentials"

    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Credential
        @{ Role = 'Admin' } = $adminCredential
    } -DefaultCredential $adminCredential

    $provider = New-IdleADIdentityProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
        AuthSessionBroker = $broker
    }

    # Workflow steps can specify different auth contexts:
    # With.AuthSessionName = 'ActiveDirectory'
    # With.AuthSessionOptions = @{ Role = 'Tier0' }

    .EXAMPLE
    # Custom broker for advanced scenarios (vault integration, MFA)
    $broker = [pscustomobject]@{}
    $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
        param($Name, $Options)
        if ($Options.Role -eq 'Tier0') {
            return Get-SecretFromVault -Name 'AD-Tier0'
        }
        return Get-SecretFromVault -Name 'AD-Admin'
    }

    $provider = New-IdleADIdentityProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
        AuthSessionBroker = $broker
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch] $AllowDelete,

        [Parameter()]
        [int] $PasswordGenerationFallbackMinLength = 24,

        [Parameter()]
        [bool] $PasswordGenerationRequireUpper = $true,

        [Parameter()]
        [bool] $PasswordGenerationRequireLower = $true,

        [Parameter()]
        [bool] $PasswordGenerationRequireDigit = $true,

        [Parameter()]
        [bool] $PasswordGenerationRequireSpecial = $true,

        [Parameter()]
        [string] $PasswordGenerationSpecialCharSet = '!@#$%&*+-_=?',

        [Parameter()]
        [AllowNull()]
        [object] $Adapter
    )

    # Check prerequisites and emit warnings if required components are missing
    $prereqs = Test-IdleADPrerequisites
    if (-not $prereqs.IsHealthy) {
        foreach ($missing in $prereqs.MissingRequired) {
            Write-Warning "AD provider prerequisite check: Required component '$missing' is not available."
        }
        foreach ($note in $prereqs.Notes) {
            Write-Warning "AD provider prerequisite check: $note"
        }
    }

    if ($null -eq $Adapter) {
        $Adapter = New-IdleADAdapter -PasswordGenerationFallbackMinLength $PasswordGenerationFallbackMinLength `
            -PasswordGenerationRequireUpper $PasswordGenerationRequireUpper `
            -PasswordGenerationRequireLower $PasswordGenerationRequireLower `
            -PasswordGenerationRequireDigit $PasswordGenerationRequireDigit `
            -PasswordGenerationRequireSpecial $PasswordGenerationRequireSpecial `
            -PasswordGenerationSpecialCharSet $PasswordGenerationSpecialCharSet
    }

    $convertToEntitlement = {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Value
        )

        return ConvertTo-IdleADEntitlement -Value $Value
    }

    $testEntitlementEquals = {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $A,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $B
        )

        $aEnt = $this.ConvertToEntitlement($A)
        $bEnt = $this.ConvertToEntitlement($B)

        if ($aEnt.Kind -ne $bEnt.Kind) {
            return $false
        }

        return [string]::Equals($aEnt.Id, $bEnt.Id, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $resolveIdentity = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        # Try GUID format first (most deterministic)
        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse($IdentityKey, [ref]$guid)) {
            try {
                $user = $adapter.GetUserByGuid($guid.ToString())
            }
            catch [System.Management.Automation.MethodException] {
                Write-Verbose "GetUserByGuid failed for GUID '$IdentityKey': $_"
                $user = $null
            }

            if ($null -ne $user) {
                return $user
            }
            throw "Identity with GUID '$IdentityKey' not found."
        }

        # Try UPN format (contains @)
        if ($IdentityKey -match '@') {
            $user = $adapter.GetUserByUpn($IdentityKey)
            if ($null -ne $user) {
                return $user
            }
            throw "Identity with UPN '$IdentityKey' not found."
        }

        # Fallback to sAMAccountName
        $user = $adapter.GetUserBySam($IdentityKey)
        if ($null -ne $user) {
            return $user
        }
        throw "Identity with sAMAccountName '$IdentityKey' not found."
    }

    $normalizeGroupId = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupId,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $group = $adapter.GetGroupById($GroupId)
        if ($null -eq $group) {
            throw "Group '$GroupId' not found."
        }

        return $group.DistinguishedName
    }

    $provider = [pscustomobject]@{
        PSTypeName  = 'IdLE.Provider.ADIdentityProvider'
        Name        = 'ADIdentityProvider'
        Adapter     = $Adapter
        AllowDelete = [bool]$AllowDelete
        PasswordGenerationFallbackMinLength = $PasswordGenerationFallbackMinLength
        PasswordGenerationRequireUpper = $PasswordGenerationRequireUpper
        PasswordGenerationRequireLower = $PasswordGenerationRequireLower
        PasswordGenerationRequireDigit = $PasswordGenerationRequireDigit
        PasswordGenerationRequireSpecial = $PasswordGenerationRequireSpecial
        PasswordGenerationSpecialCharSet = $PasswordGenerationSpecialCharSet
    }

    # Helper method to extract credential from AuthSession and create effective adapter
    $getEffectiveAdapter = {
        param(
            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        # If no AuthSession, return the default adapter
        # Only validate prerequisites for the default adapter if it's the real one (not injected for tests)
        # Check TypeNames collection (PSTypeName in hashtable adds to TypeNames, not as a property)
        if ($null -eq $AuthSession) {
            $isRealAdapter = ($this.Adapter.PSObject.TypeNames -contains 'IdLE.ADAdapter')
            
            if ($isRealAdapter) {
                $prereqCheck = Test-IdleADPrerequisites
                if (-not $prereqCheck.IsHealthy) {
                    $missingList = $prereqCheck.MissingRequired -join ', '
                    $errorMsg = "AD provider operation cannot proceed. Required prerequisite(s) missing: $missingList"
                    if ($prereqCheck.Notes.Count -gt 0) {
                        $errorMsg += "`n" + ($prereqCheck.Notes -join "`n")
                    }
                    throw $errorMsg
                }
            }
            return $this.Adapter
        }

        $credential = $null
        if ($AuthSession -is [PSCredential]) {
            $credential = $AuthSession
        }
        elseif ($AuthSession.PSObject.Properties.Name -contains 'Credential') {
            $credential = $AuthSession.Credential
        }

        if ($null -ne $credential) {
            # Creating new adapter with credential - validate prerequisites
            $prereqCheck = Test-IdleADPrerequisites
            if (-not $prereqCheck.IsHealthy) {
                $missingList = $prereqCheck.MissingRequired -join ', '
                $errorMsg = "AD provider operation cannot proceed. Required prerequisite(s) missing: $missingList"
                if ($prereqCheck.Notes.Count -gt 0) {
                    $errorMsg += "`n" + ($prereqCheck.Notes -join "`n")
                }
                throw $errorMsg
            }
            return New-IdleADAdapter -Credential $credential `
                -PasswordGenerationFallbackMinLength $this.PasswordGenerationFallbackMinLength `
                -PasswordGenerationRequireUpper $this.PasswordGenerationRequireUpper `
                -PasswordGenerationRequireLower $this.PasswordGenerationRequireLower `
                -PasswordGenerationRequireDigit $this.PasswordGenerationRequireDigit `
                -PasswordGenerationRequireSpecial $this.PasswordGenerationRequireSpecial `
                -PasswordGenerationSpecialCharSet $this.PasswordGenerationSpecialCharSet
        }

        return $this.Adapter
    }

    $provider | Add-Member -MemberType ScriptMethod -Name GetEffectiveAdapter -Value $getEffectiveAdapter -Force
    $provider | Add-Member -MemberType ScriptMethod -Name ConvertToEntitlement -Value $convertToEntitlement -Force
    $provider | Add-Member -MemberType ScriptMethod -Name TestEntitlementEquals -Value $testEntitlementEquals -Force
    $provider | Add-Member -MemberType ScriptMethod -Name ResolveIdentity -Value $resolveIdentity -Force
    $provider | Add-Member -MemberType ScriptMethod -Name NormalizeGroupId -Value $normalizeGroupId -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
        $caps = @(
            'IdLE.Identity.Read'
            'IdLE.Identity.List'
            'IdLE.Identity.Create'
            'IdLE.Identity.Attribute.Ensure'
            'IdLE.Identity.Move'
            'IdLE.Identity.Disable'
            'IdLE.Identity.Enable'
            'IdLE.Entitlement.List'
            'IdLE.Entitlement.Grant'
            'IdLE.Entitlement.Revoke'
        )

        if ($this.AllowDelete) {
            $caps += 'IdLE.Identity.Delete'
        }

        return $caps
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        # Validate adapter is available
        $this.GetEffectiveAdapter($AuthSession) | Out-Null

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $attributes = @{}
        if ($null -ne $user.GivenName) { $attributes['GivenName'] = $user.GivenName }
        if ($null -ne $user.Surname) { $attributes['Surname'] = $user.Surname }
        if ($null -ne $user.DisplayName) { $attributes['DisplayName'] = $user.DisplayName }
        if ($null -ne $user.Description) { $attributes['Description'] = $user.Description }
        if ($null -ne $user.Department) { $attributes['Department'] = $user.Department }
        if ($null -ne $user.Title) { $attributes['Title'] = $user.Title }
        if ($null -ne $user.EmailAddress) { $attributes['EmailAddress'] = $user.EmailAddress }
        if ($null -ne $user.UserPrincipalName) { $attributes['UserPrincipalName'] = $user.UserPrincipalName }
        if ($null -ne $user.sAMAccountName) { $attributes['sAMAccountName'] = $user.sAMAccountName }
        if ($null -ne $user.DistinguishedName) { $attributes['DistinguishedName'] = $user.DistinguishedName }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Identity'
            IdentityKey = $IdentityKey
            Enabled     = [bool]$user.Enabled
            Attributes  = $attributes
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name ListIdentities -Value {
        param(
            [Parameter()]
            [hashtable] $Filter,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $users = $adapter.ListUsers($Filter)
        $identityKeys = @()
        foreach ($user in $users) {
            $identityKeys += $user.ObjectGuid.ToString()
        }
        return $identityKeys
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name CreateIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Attributes,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        # Validate attributes against contract (strict mode - will throw on unsupported attributes)
        $validationResult = Test-IdleADAttributeContract -Attributes $Attributes -Operation 'CreateIdentity'

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        try {
            $existing = $this.ResolveIdentity($IdentityKey, $AuthSession)
            if ($null -ne $existing) {
                return [pscustomobject]@{
                    PSTypeName  = 'IdLE.ProviderResult'
                    Operation   = 'CreateIdentity'
                    IdentityKey = $IdentityKey
                    Changed     = $false
                }
            }
        }
        catch {
            # Identity does not exist, proceed with creation (expected for idempotent create)
            Write-Verbose "Identity '$IdentityKey' does not exist, proceeding with creation"
        }

        $enabled = $true
        if ($Attributes.ContainsKey('Enabled')) {
            $enabled = [bool]$Attributes['Enabled']
        }

        $user = $adapter.NewUser($IdentityKey, $Attributes, $enabled)

        # Emit observability event
        if ($this.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $this.EventSink) {
            $eventData = @{
                IdentityKey = $IdentityKey
                Requested   = $validationResult.Requested
            }
            $this.EventSink.WriteEvent('Provider.AD.CreateIdentity.AttributesRequested', 'Attributes requested during identity creation', 'CreateIdentity', $eventData)
        }

        # Build result with optional password generation info
        $result = [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'CreateIdentity'
            IdentityKey = $IdentityKey
            Changed     = $true
        }

        # Handle password generation output (if password was generated)
        if ($null -ne $user.PSObject.Properties['_GeneratedPasswordInfo']) {
            $passwordInfo = $user._GeneratedPasswordInfo
            
            # Always include ProtectedString for reveal path (DPAPI-scoped)
            $result | Add-Member -MemberType NoteProperty -Name 'GeneratedAccountPasswordProtected' -Value $passwordInfo.ProtectedString
            
            # Check for explicit opt-in to plaintext output
            $allowPlainTextOutput = $false
            if ($Attributes.ContainsKey('AllowPlainTextPasswordOutput')) {
                $allowPlainTextOutput = [bool]$Attributes['AllowPlainTextPasswordOutput']
            }
            
            if ($allowPlainTextOutput) {
                # Include plaintext password only when explicitly requested
                $result | Add-Member -MemberType NoteProperty -Name 'GeneratedAccountPasswordPlainText' -Value $passwordInfo.PlainText
                Write-Verbose "AD Provider: Plaintext password output enabled (AllowPlainTextPasswordOutput=true)"
            }
            
            # Add metadata about password generation
            $result | Add-Member -MemberType NoteProperty -Name 'PasswordGenerated' -Value $true
            $result | Add-Member -MemberType NoteProperty -Name 'PasswordGenerationPolicyUsed' -Value $passwordInfo.UsedPolicy
            
            Write-Verbose "AD Provider: Password was generated using $($passwordInfo.UsedPolicy) policy"
        }

        return $result
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DeleteIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        if (-not $this.AllowDelete) {
            throw "Delete capability is not enabled. Set AllowDelete = `$true when creating the provider."
        }

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        try {
            $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
            $adapter.DeleteUser($user.DistinguishedName)
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'DeleteIdentity'
                IdentityKey = $IdentityKey
                Changed     = $true
            }
        }
        catch {
            # Check if identity doesn't exist (idempotent delete)
            # Use exception type if available, otherwise fall back to message check
            $isNotFound = $false
            if ($_.Exception.GetType().FullName -eq 'Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException') {
                $isNotFound = $true
            }
            elseif ($_.Exception.Message -match 'not found|cannot be found|does not exist') {
                $isNotFound = $true
            }

            if ($isNotFound) {
                return [pscustomobject]@{
                    PSTypeName  = 'IdLE.ProviderResult'
                    Operation   = 'DeleteIdentity'
                    IdentityKey = $IdentityKey
                    Changed     = $false
                }
            }
            throw
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
            [object] $Value,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        # Validate attribute against contract (strict mode - will throw on unsupported attributes)
        $validationResult = Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName $Name

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $currentValue = $null
        if ($user.PSObject.Properties.Name -contains $Name) {
            $currentValue = $user.$Name
        }

        $changed = $false
        if ($currentValue -ne $Value) {
            # Special handling for Manager attribute - resolve to DN
            $valueToSet = $Value
            if ($Name -eq 'Manager' -and $null -ne $Value) {
                $valueToSet = $adapter.ResolveManagerDN($Value)
            }
            
            $adapter.SetUser($user.DistinguishedName, $Name, $valueToSet)
            $changed = $true

            # Emit observability event
            if ($this.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $this.EventSink) {
                $eventData = @{
                    IdentityKey  = $IdentityKey
                    AttributeName = $Name
                    OldValue     = $currentValue
                    NewValue     = $Value
                }
                $this.EventSink.WriteEvent('Provider.AD.EnsureAttribute.AttributeChanged', "Attribute '$Name' changed", 'EnsureAttribute', $eventData)
            }
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnsureAttribute'
            IdentityKey = $IdentityKey
            Changed     = $changed
            Name        = $Name
            Value       = $Value
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name MoveIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $TargetContainer,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $currentOu = $user.DistinguishedName -replace '^CN=[^,]+,', ''

        $changed = $false
        if ($currentOu -ne $TargetContainer) {
            $adapter.MoveObject($user.DistinguishedName, $TargetContainer)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName       = 'IdLE.ProviderResult'
            Operation        = 'MoveIdentity'
            IdentityKey      = $IdentityKey
            Changed          = $changed
            TargetContainer  = $TargetContainer
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $changed = $false
        if ($user.Enabled -ne $false) {
            $adapter.DisableUser($user.DistinguishedName)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'DisableIdentity'
            IdentityKey = $IdentityKey
            Changed     = $changed
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name EnableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $changed = $false
        if ($user.Enabled -ne $true) {
            $adapter.EnableUser($user.DistinguishedName)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnableIdentity'
            IdentityKey = $IdentityKey
            Changed     = $changed
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $groups = $adapter.GetUserGroups($user.DistinguishedName)

        $result = @()
        foreach ($group in $groups) {
            $result += [pscustomobject]@{
                PSTypeName  = 'IdLE.Entitlement'
                Kind        = 'Group'
                Id          = $group.DistinguishedName
                DisplayName = $group.Name
            }
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
            [object] $Entitlement,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $normalized = $this.ConvertToEntitlement($Entitlement)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
        $groupDn = $this.NormalizeGroupId($normalized.Id, $AuthSession)

        $currentGroups = $this.ListEntitlements($IdentityKey, $AuthSession)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -eq 0) {
            $adapter.AddGroupMember($groupDn, $user.DistinguishedName)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'GrantEntitlement'
            IdentityKey = $IdentityKey
            Changed     = $changed
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
            [object] $Entitlement,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $adapter = $this.GetEffectiveAdapter($AuthSession)

        $normalized = $this.ConvertToEntitlement($Entitlement)

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
        $groupDn = $this.NormalizeGroupId($normalized.Id, $AuthSession)

        $currentGroups = $this.ListEntitlements($IdentityKey, $AuthSession)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -gt 0) {
            $adapter.RemoveGroupMember($groupDn, $user.DistinguishedName)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'RevokeEntitlement'
            IdentityKey = $IdentityKey
            Changed     = $changed
            Entitlement = $normalized
        }
    } -Force

    return $provider
}
