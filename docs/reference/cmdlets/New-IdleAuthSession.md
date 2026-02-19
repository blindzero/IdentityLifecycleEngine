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
New-IdleAuthSession [[-SessionMap] &lt;Hashtable&gt;] [[-DefaultAuthSession] &lt;Object&gt;] [[-AuthSessionType] &lt;String&gt;]
 [-ProgressAction &lt;ActionPreference&gt;] [&lt;CommonParameters&gt;]
```

## DESCRIPTION
Creates an AuthSessionBroker that routes authentication based on user-defined options.
The broker is used by steps to acquire credentials at runtime without embedding
secrets in workflows or provider construction.

This is a thin wrapper that delegates to IdLE.Core\New-IdleAuthSessionBroker.

## EXAMPLES

### EXAMPLE 1
```
# Simple broker with single credential
$broker = New-IdleAuthSession -DefaultAuthSession $credential -AuthSessionType 'Credential'
```

### EXAMPLE 2
```
# Mixed-type broker for AD + EXO
$broker = New-IdleAuthSession -SessionMap @{
    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Credential = $adCred }
    @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Credential = $token }
}
```

## PARAMETERS

### -SessionMap
A hashtable that maps session configurations to auth sessions.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
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
Optional default authentication session type.
When provided, allows simple (untyped) 
session values.
When not provided, values must be typed descriptors.

Valid values:
- 'OAuth': Token-based authentication (e.g., Microsoft Graph, Exchange Online)
- 'PSRemoting': PowerShell remoting execution context (e.g., Entra Connect)
- 'Credential': Credential-based authentication (e.g., Active Directory, mock providers)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
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

### PSCustomObject with AcquireAuthSession method

## NOTES

### Framework-Reserved Keys

The execution framework automatically injects `CorrelationId` and `Actor` into auth session options during plan execution.

**Behavior:**
- **AuthSessionName-only patterns** (e.g., `@{ AuthSessionName = 'Entra' }`): Framework keys are automatically ignored during matching, so simple patterns work as expected
- **Multi-key patterns** (e.g., `@{ AuthSessionName = 'AD'; Actor = 'ops-user' }`): ALL keys including `Actor` and `CorrelationId` participate in matching, enabling actor-based routing

**Warning:** Using `Actor` or `CorrelationId` in patterns will trigger a warning because these values are framework-controlled and change per execution. Consider using user-defined routing keys (like `Role`, `Environment`, `Tier`) instead for more predictable behavior.

For detailed documentation, see: Get-Help IdLE.Core\New-IdleAuthSessionBroker -Full

## RELATED LINKS
