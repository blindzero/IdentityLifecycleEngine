---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleAuthSession

## SYNOPSIS
Creates a simple AuthSessionBroker for use with IdLE providers.

## SYNTAX

```
New-IdleAuthSession [-SessionMap] <Hashtable> [[-DefaultAuthSession] <Object>] -AuthSessionType <String>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Creates an AuthSessionBroker that routes authentication based on user-defined options.
The broker is used by steps to acquire credentials at runtime without embedding
secrets in workflows or provider construction.

This is a thin wrapper that delegates to IdLE.Core\New-IdleAuthSessionBroker.

## EXAMPLES

### EXAMPLE 1
```
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
} -AuthSessionType 'Credential'
```

## PARAMETERS

### -SessionMap
A hashtable that maps session configurations to auth sessions.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DefaultAuthSession
Optional default auth session to return when no session options are provided.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AuthSessionType
Specifies the type of authentication session. This determines validation rules,
lifecycle management, and telemetry behavior.

Valid values:
- 'OAuth': Token-based authentication (e.g., Microsoft Graph, Exchange Online)
- 'PSRemoting': PowerShell remoting execution context (e.g., Entra Connect)
- 'Credential': Credential-based authentication (e.g., Active Directory, mock providers)

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: OAuth, PSRemoting, Credential

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
Controls the display of progress information during cmdlet execution.

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

### PSCustomObject with AcquireAuthSession method
## NOTES
For detailed documentation, see: Get-Help IdLE.Core\New-IdleAuthSessionBroker -Full

## RELATED LINKS
