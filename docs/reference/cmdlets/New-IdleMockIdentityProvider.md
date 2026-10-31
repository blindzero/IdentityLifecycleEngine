---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleMockIdentityProvider

## SYNOPSIS
Creates an in-memory identity provider for tests and demos.

## SYNTAX

```
New-IdleMockIdentityProvider [[-InitialStore] &lt;Hashtable&gt;] [-ProgressAction &lt;ActionPreference&gt;]
 [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This provider is deterministic and has no external dependencies.
It is designed to be used in unit tests, contract tests, and example workflows.

The provider keeps all state in a private in-memory store that is scoped to the
returned provider object instance (no global state).
This makes tests predictable.

## EXAMPLES

### EXAMPLE 1
```
$provider = New-IdleMockIdentityProvider
$provider.EnsureAttribute('user1', 'Department', 'IT') | Out-Null
$provider.GetIdentity('user1') | Format-List
```

### EXAMPLE 2
```
$provider = New-IdleMockIdentityProvider -InitialStore @{
    'user1' = @{
        IdentityKey = 'user1'
        Enabled     = $true
        Attributes  = @{
            Department = 'IT'
        }
        Entitlements = @(
            @{ Kind = 'Group'; Id = 'demo-group' }
        )
    }
}
```

## PARAMETERS

### -InitialStore
Optional initial store content.
This is useful when a test wants to start with
pre-seeded identities.
The input is shallow-copied to avoid unintended mutations
from the outside.

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
