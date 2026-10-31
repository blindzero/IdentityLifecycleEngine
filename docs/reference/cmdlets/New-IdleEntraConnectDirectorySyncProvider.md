---
external help file: IdLE-help.xml
Module Name: IdLE
online version:
schema: 2.0.0
---

# New-IdleEntraConnectDirectorySyncProvider

## SYNOPSIS
Creates an Entra Connect directory sync provider for IdLE.

## SYNTAX

```
New-IdleEntraConnectDirectorySyncProvider [-ProgressAction &lt;ActionPreference&gt;] [&lt;CommonParameters&gt;]
```

## DESCRIPTION
This provider triggers and monitors Entra ID Connect (ADSync) sync cycles on an
on-premises server via remote execution.

The provider uses a credential AuthSession provided by the host and establishes
a PSRemoting session to the target Entra Connect server internally.

No interactive prompts are made; elevation and authentication are the host's responsibility
via the AuthSessionBroker.

## EXAMPLES

### EXAMPLE 1
```
$provider = New-IdleEntraConnectDirectorySyncProvider
$provider.GetCapabilities()
# Returns: @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
```

### EXAMPLE 2
```
# With a credential from AuthSessionBroker (AuthSessionType='Credential')
$credential = Get-Credential
$provider = New-IdleEntraConnectDirectorySyncProvider
$result = $provider.StartSyncCycle('Delta', 'ad-sync1.corp.local', $credential)
```

## PARAMETERS

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

### PSCustomObject
### Provider instance with methods: GetCapabilities(), StartSyncCycle(PolicyType, ComputerName, AuthSession), GetSyncCycleState(ComputerName, AuthSession)
## NOTES

## RELATED LINKS
