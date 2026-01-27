---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdlePlan

## SYNOPSIS
Creates a deterministic plan from a lifecycle request and a workflow definition.

## SYNTAX

```
New-IdlePlan [-WorkflowPath] <String> [-Request] <Object> [[-Providers] <Object>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Delegates plan building to IdLE.Core and returns a plan artifact.
Providers are passed through for later increments.

## EXAMPLES

### EXAMPLE 1
```
$plan = New-IdlePlan -WorkflowPath ./workflows/joiner.psd1 -Request $request -Providers $providers
```

## PARAMETERS

### -WorkflowPath
Path to the workflow definition file (PSD1).

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

### -Request
The lifecycle request object created by New-IdleLifecycleRequest.

```yaml
Type: Object
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Providers
Provider registry/collection passed through to planning.
(Structure to be defined later.)

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

### -ProgressAction
`{{ Fill ProgressAction Description }}`

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

### System.Object
## NOTES

## RELATED LINKS
