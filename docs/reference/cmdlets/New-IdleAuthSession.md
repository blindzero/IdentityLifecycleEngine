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
New-IdleAuthSession [-SessionMap] &lt;Hashtable&gt; [[-DefaultCredential] &lt;PSCredential&gt;]
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
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
}
```

## PARAMETERS

### -SessionMap
A hashtable that maps session configurations to credentials.

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

### -DefaultCredential
Optional default credential to return when no session options are provided.

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
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
For detailed documentation, see: Get-Help IdLE.Core\New-IdleAuthSessionBroker -Full

## RELATED LINKS
