---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleADIdentityProvider

## SYNOPSIS
Creates an Active Directory identity provider for IdLE.

## SYNTAX

```
New-IdleADIdentityProvider [-AllowDelete] [[-PasswordGenerationFallbackMinLength] &lt;Int32&gt;]
 [[-PasswordGenerationRequireUpper] &lt;Boolean&gt;] [[-PasswordGenerationRequireLower] &lt;Boolean&gt;]
 [[-PasswordGenerationRequireDigit] &lt;Boolean&gt;] [[-PasswordGenerationRequireSpecial] &lt;Boolean&gt;]
 [[-PasswordGenerationSpecialCharSet] &lt;String&gt;] [[-Adapter] &lt;Object&gt;] [-ProgressAction &lt;ActionPreference&gt;]
 [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This provider integrates with on-premises Active Directory environments.
It requires the ActiveDirectory PowerShell module (RSAT) and runs on Windows only.

The provider supports common identity operations (Create, Read, Disable, Enable, Move, Delete)
and group entitlement management (List, Grant, Revoke).

Identity addressing supports:
- GUID (ObjectGuid) - pattern: ^\[0-9a-fA-F-\]{36}$ or N-format
- UPN (UserPrincipalName) - contains @
- sAMAccountName - default fallback

Authentication:
Provider methods accept an optional AuthSession parameter for runtime credential
selection via the AuthSessionBroker.
This enables multi-role scenarios (e.g.,
Tier0 vs.
Admin) without embedding credentials in the provider or workflow.

By default, the provider uses integrated authentication (run-as credentials).
For runtime credential selection, configure an AuthSessionBroker and use
With.AuthSessionName and With.AuthSessionOptions in step definitions.

## EXAMPLES

### EXAMPLE 1
```
# Use integrated authentication (run-as)
$provider = New-IdleADIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
}
```

### EXAMPLE 2
```
# Custom password generation fallback configuration
$provider = New-IdleADIdentityProvider -PasswordGenerationFallbackMinLength 32 -PasswordGenerationSpecialCharSet '!@#$%^&*()'
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
}
```

### EXAMPLE 3
```
# Multi-role scenario with New-IdleAuthSessionBroker (recommended)
$tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
$adminCredential = Get-Credential -Message "Enter regular admin credentials"
$authSessionBroker = New-IdleAuthSessionBroker -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
    @{ Role = 'Admin' } = $adminCredential
} -DefaultCredential $adminCredential
$provider = New-IdleADIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $authSessionBroker
}
# Workflow steps can specify different auth contexts:
# With.AuthSessionName = 'ActiveDirectory'
# With.AuthSessionOptions = @{ Role = 'Tier0' }
```

### EXAMPLE 4
```
# Custom broker for advanced scenarios (vault integration, MFA)
$authSessionBroker = [pscustomobject]@{}
$authSessionBroker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
    param($Name, $Options)
    if ($Options.Role -eq 'Tier0') {
        return Get-SecretFromVault -Name 'AD-Tier0'
    }
    return Get-SecretFromVault -Name 'AD-Admin'
}
$provider = New-IdleADIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $authSessionBroker
}
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

### -PasswordGenerationFallbackMinLength
Fallback minimum password length when domain policy cannot be read.
Default is 24.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: 24
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordGenerationRequireUpper
Fallback requirement for uppercase characters in generated passwords.
Default is $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordGenerationRequireLower
Fallback requirement for lowercase characters in generated passwords.
Default is $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordGenerationRequireDigit
Fallback requirement for digit characters in generated passwords.
Default is $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordGenerationRequireSpecial
Fallback requirement for special characters in generated passwords.
Default is $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordGenerationSpecialCharSet
Set of special characters to use in generated passwords.
Default is '!@#$%&*+-_=?'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: !@#$%&*+-_=?
Accept pipeline input: False
Accept wildcard characters: False
```

### -Adapter
Internal parameter for dependency injection during testing.
Allows unit tests to inject
a fake AD adapter without requiring a real Active Directory environment.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
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

## NOTES

## RELATED LINKS
