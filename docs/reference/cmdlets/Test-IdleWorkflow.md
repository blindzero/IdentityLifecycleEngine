---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# Test-IdleWorkflow

## SYNOPSIS
Validates an IdLE workflow definition file.

## SYNTAX

```
Test-IdleWorkflow [-WorkflowPath] <String> [[-Request] <Object>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Loads and strictly validates a workflow definition (PSD1).
Throws on validation errors.

## EXAMPLES

### EXAMPLE 1
```
Test-IdleWorkflow -WorkflowPath ./workflows/joiner.psd1 -Request $request
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
Optional lifecycle request for validating compatibility (LifecycleEvent match).

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

### -ProgressAction
{{ Fill ProgressAction Description }}

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
