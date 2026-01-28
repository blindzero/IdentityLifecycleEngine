---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# Invoke-IdlePlan

## SYNOPSIS
Executes an IdLE plan.

## SYNTAX

```
Invoke-IdlePlan [-Plan] &lt;Object&gt; [[-Providers] &lt;Hashtable&gt;] [[-EventSink] &lt;Object&gt;]
 [[-ExecutionOptions] &lt;Hashtable&gt;] [-ProgressAction &lt;ActionPreference&gt;] [-WhatIf] [-Confirm]
 [&lt;CommonParameters&gt;]
```

## DESCRIPTION
Executes a plan deterministically and emits structured events.
Delegates execution to IdLE.Core.

## EXAMPLES

### EXAMPLE 1
```
Invoke-IdlePlan -Plan $plan -Providers $providers
```

### EXAMPLE 2
```
$execOptions = @{
    RetryProfiles = @{
        Default = @{ MaxAttempts = 3; InitialDelayMilliseconds = 200 }
        ExchangeOnline = @{ MaxAttempts = 6; InitialDelayMilliseconds = 500 }
    }
    DefaultRetryProfile = 'Default'
}
Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $execOptions
```

## PARAMETERS

### -Plan
The plan object created by New-IdlePlan.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -Providers
Provider registry/collection passed through to execution.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -EventSink
Optional external event sink for streaming.
Must be an object with a WriteEvent(event) method.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExecutionOptions
Optional host-owned execution options.
Supports retry profile configuration.
Must be a hashtable with optional keys: RetryProfiles, DefaultRetryProfile.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
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

### PSCustomObject (PSTypeName: IdLE.ExecutionResult)
## NOTES

## RELATED LINKS
