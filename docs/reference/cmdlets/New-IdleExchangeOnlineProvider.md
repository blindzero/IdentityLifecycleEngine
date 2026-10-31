---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleExchangeOnlineProvider

## SYNOPSIS
Creates an Exchange Online mailbox provider for IdLE.

## SYNTAX

```
New-IdleExchangeOnlineProvider [[-Adapter] &lt;Object&gt;] [-ProgressAction &lt;ActionPreference&gt;] [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This provider integrates with Exchange Online for mailbox lifecycle management operations.
It supports mailbox reporting, type conversions, and Out of Office configuration management.

The provider implements the mailbox-specific provider contract used by IdLE.Steps.Mailbox.

Identity addressing:
- UserPrincipalName (UPN) - preferred
- Primary SMTP address (email)
- Mailbox GUID (for deterministic operations)

The canonical identity key for all outputs is the primary SMTP address.

Authentication:
Provider methods accept an optional AuthSession parameter for runtime credential
selection via the AuthSessionBroker.
The provider supports multiple auth session formats:
- String access token (for future Graph API integration)
- Object with AccessToken property
- Object with GetAccessToken() method
- PSCredential (for certificate-based auth)

By default, mailbox steps should use:
- With.AuthSessionName = 'ExchangeOnline'
- \`With.AuthSessionOptions = @{ Role = 'Admin' }\` (or other routing keys)

Prerequisites:
- ExchangeOnlineManagement PowerShell module must be installed
- For app-only (certificate) auth: Windows platform required (MVP limitation)
- Authenticated session must be established before using provider methods

## EXAMPLES

### EXAMPLE 1
```
# Basic usage with delegated auth
# Host establishes connection first
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
$provider = New-IdleExchangeOnlineProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    ExchangeOnline = $provider
}
```

### EXAMPLE 2
```
# Certificate-based app-only auth (Windows only)
# Host establishes connection first
Connect-ExchangeOnline -CertificateThumbprint $thumbprint -AppId $appId -Organization $tenantId
$provider = New-IdleExchangeOnlineProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    ExchangeOnline = $provider
}
```

## PARAMETERS

### -Adapter
Internal parameter for dependency injection during testing.
Allows unit tests to inject
a fake adapter without requiring a real Exchange Online environment.

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

### PSCustomObject with IdLE mailbox provider contract methods
## NOTES
Requires Exchange Online Management module and appropriate permissions:
- Exchange.ManageAsApp (app-only)
- Exchange Administrator or Global Administrator role (delegated)
- Required role: Mail Recipients (manage mailboxes)

See the IdLE provider documentation for detailed setup.

## RELATED LINKS
