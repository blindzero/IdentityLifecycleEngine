---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleEntraIDIdentityProvider

## SYNOPSIS
Creates a Microsoft Entra ID identity provider for IdLE.

## SYNTAX

```
New-IdleEntraIDIdentityProvider [-AllowDelete] [[-Adapter] &lt;Object&gt;] [-ProgressAction &lt;ActionPreference&gt;]
 [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This provider integrates with Microsoft Entra ID (formerly Azure Active Directory)
via the Microsoft Graph API (v1.0).
It supports both delegated and app-only authentication
via the host-provided AuthSessionBroker pattern.

The provider supports common identity operations (Create, Read, Disable, Enable, Delete)
and entitlement management for groups and Administrative Units (List, Grant, Revoke).

Identity addressing supports:
- objectId (GUID string) - most deterministic
- UserPrincipalName (UPN) - contains @
- mail - email address

The canonical identity key for all outputs is the user objectId (GUID string).

Authentication:
Provider methods accept an optional AuthSession parameter for runtime credential
selection via the AuthSessionBroker.
The provider supports multiple auth session formats:
- String access token (Bearer token)
- Object with AccessToken property
- Object with GetAccessToken() method
- PSCredential (must contain AccessToken in password field for Graph API)

By default, steps should use:
- With.AuthSessionName = 'MicrosoftGraph'
- With.AuthSessionOptions with routing keys, e.g.
Role = 'Admin'

## EXAMPLES

### EXAMPLE 1
```
# Basic usage with delegated auth
# Host obtains token via secure method (not shown here - see provider documentation)
$accessToken = Get-SecureGraphToken
$authSessionBroker = New-IdleAuthSessionBroker -SessionMap @{
    @{} = $accessToken
} -DefaultCredential $accessToken
$provider = New-IdleEntraIDIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $authSessionBroker
}
```

### EXAMPLE 2
```
# Multi-role scenario
$tier0Token = Get-GraphTokenForTier0  # host-managed auth
$adminToken = Get-GraphTokenForAdmin
$authSessionBroker = New-IdleAuthSessionBroker -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Token
    @{ Role = 'Admin' } = $adminToken
} -DefaultCredential $adminToken
$provider = New-IdleEntraIDIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $authSessionBroker
}
# Workflow steps specify: With.AuthSessionOptions = @{ Role = 'Tier0' }
```

### EXAMPLE 3
```
# Enable delete capability (opt-in)
$provider = New-IdleEntraIDIdentityProvider -AllowDelete
```

## PARAMETERS

### -AllowDelete
Opt-in flag to enable the IdLE.Identity.Delete capability.
When $true, the provider advertises the Delete capability and allows identity deletion.
Default is $false for safety.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Adapter
Internal parameter for dependency injection during testing.
Allows unit tests to inject
a mock Graph adapter without requiring a real Entra ID environment.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
TODO: ProgressAction Description

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### PSCustomObject with IdLE provider contract methods
## NOTES
Requires Microsoft Graph API permissions (delegated or app-only):
- User.Read.All, User.ReadWrite.All
- Group.Read.All, GroupMember.ReadWrite.All
- AdministrativeUnit.Read.All (for ListEntitlements/GrantEntitlement/RevokeEntitlement with Kind=AdministrativeUnit)
- AdministrativeUnit.ReadWrite.All (for Grant/Revoke with Kind=AdministrativeUnit)
- For delete: User.ReadWrite.All

See docs/reference/providers/provider-entraID.md for detailed permission requirements.

## RELATED LINKS
