---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleRequest

## SYNOPSIS
Creates a lifecycle request object.

## SYNTAX

```
New-IdleRequest [-LifecycleEvent] &lt;String&gt; [[-CorrelationId] &lt;String&gt;] [[-Actor] &lt;String&gt;]
 [[-IdentityKeys] &lt;Hashtable&gt;] [[-Intent] &lt;Hashtable&gt;] [[-Context] &lt;Hashtable&gt;]
 [-ProgressAction &lt;ActionPreference&gt;] [&lt;CommonParameters&gt;]
```

## DESCRIPTION
Creates and normalizes an IdLE LifecycleRequest representing business intent
(e.g.
Joiner/Mover/Leaver).
CorrelationId is generated if missing.
Actor is optional.

## EXAMPLES

### EXAMPLE 1
```
# Minimal Joiner request - CorrelationId is auto-generated, Intent/Context default to empty
New-IdleRequest -LifecycleEvent Joiner -CorrelationId (New-Guid) -IdentityKeys @{ EmployeeId = '12345' }
```

### EXAMPLE 2
```
# Joiner request with caller-provided action inputs (Intent) and read-only associated context (Context)
New-IdleRequest -LifecycleEvent Joiner -CorrelationId (New-Guid) -IdentityKeys @{ EmployeeId = '12345' } -Intent @{ Department = 'Engineering'; Title = 'Engineer' } -Context @{ Identity = @{ ObjectId = 'abc-123' } }
```

## PARAMETERS

### -LifecycleEvent
The lifecycle event name (e.g.
Joiner, Mover, Leaver).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -CorrelationId
Correlation identifier for audit/event correlation.
Generated if missing.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Actor
Optional actor claim who initiated the request.
Not required by the core engine in V1.

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

### -IdentityKeys
A hashtable of system-neutral identity keys (e.g.
EmployeeId, UPN, ObjectId).

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: @{}
Accept pipeline input: False
Accept wildcard characters: False
```

### -Intent
A hashtable containing the caller-provided action inputs for the workflow (attributes,
entitlements, operator flags, etc.).

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: @{}
Accept pipeline input: False
Accept wildcard characters: False
```

### -Context
A hashtable containing read-only associated context provided by the host or resolvers
(e.g.
identity snapshots, device hints).
Must not be treated as mutable state within IdLE.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: @{}
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

### IdleLifecycleRequest
## NOTES

## RELATED LINKS
