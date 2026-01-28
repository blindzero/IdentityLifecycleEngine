---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# Export-IdlePlan

## SYNOPSIS
Exports an IdLE LifecyclePlan as a canonical JSON artifact.

## SYNTAX

```
Export-IdlePlan [-Plan] &lt;Object&gt; [[-Path] &lt;String&gt;] [-PassThru] [-ProgressAction &lt;ActionPreference&gt;]
 [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This cmdlet is the **user-facing** wrapper exposed by the IdLE meta module.

It delegates to IdLE.Core's \`Export-IdlePlanObject\`, which implements the canonical
plan export contract.

By default, the cmdlet returns a pretty-printed JSON string.
If -Path is provided,
the JSON is written to disk as UTF-8 (no BOM).
Use -PassThru to also return the JSON
string when writing a file.

## EXAMPLES

### EXAMPLE 1
```
$plan = New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry
$plan | Export-IdlePlan
```

Exports the plan and returns the JSON string.

### EXAMPLE 2
```
New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlan -Path ./artifacts/plan.json
```

Exports the plan and writes the JSON to a file.

### EXAMPLE 3
```
New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlan -Path ./artifacts/plan.json -PassThru
```

Writes the file and also returns the JSON string.

## PARAMETERS

### -Plan
The LifecyclePlan object to export.
Accepts pipeline input.

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

### -Path
Optional file path to write the JSON artifact to.

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

### -PassThru
When -Path is used, returns the JSON string in addition to writing the file.

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

### System.String
## NOTES

## RELATED LINKS
