Set-StrictMode -Version Latest

<#
.SYNOPSIS
Step-specific test helpers for IdLE tests.

.DESCRIPTION
This file contains helper functions, fixtures, and test doubles specifically
related to step testing.

This file is sourced by tests/_testHelpers.ps1 and should not be dot-sourced
directly by test files.
#>

function New-IdleTestStepMetadata {
    <#
    .SYNOPSIS
    Creates test step metadata for custom step types used in tests.

    .DESCRIPTION
    Helper function to create StepMetadata entries for test-specific step types.
    By default, creates metadata with no required capabilities, no Provider and a permissive WithSchema
    that accepts any With key (@{ Keys = @{}; AllowAdditionalKeys = $true }). This allows test workflows to use
    arbitrary With.* keys without schema validation failures.

    .PARAMETER StepTypes
    Array of step type names to create metadata for.

    .PARAMETER RequiredCapabilities
    Hashtable mapping step types to their required capabilities.

    .PARAMETER WithSchemas
    Hashtable mapping step types to their WithSchema definitions. Step types not in this
    hashtable receive the default permissive schema: @{ Keys = @{}; AllowAdditionalKeys = $true }.

    .PARAMETER Providers
    Hashtable mapping step types to their default provider alias. Listed step types declare
    Provider = @{ DefaultAlias = '<alias>' }, so their handlers receive -Provider.

    .EXAMPLE
    $metadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.ResolveIdentity', 'Test.IdLE.Step.Primary')

    .EXAMPLE
    $metadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Custom') -RequiredCapabilities @{
        'Test.IdLE.Step.Custom' = @('Custom.IdLE.Capability.Test')
    }

    .EXAMPLE
    $metadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Strict') -WithSchemas @{
        'Test.IdLE.Step.Strict' = @{ Keys = @{ IdentityKey = @{ Type = 'String'; Required = $true } } }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $StepTypes,

        [Parameter()]
        [hashtable] $RequiredCapabilities = @{},

        [Parameter()]
        [hashtable] $WithSchemas = @{},

        [Parameter()]
        [hashtable] $Providers = @{}
    )

    $metadata = @{}
    foreach ($stepType in $StepTypes) {
        $caps = if ($RequiredCapabilities.ContainsKey($stepType)) {
            $RequiredCapabilities[$stepType]
        }
        else {
            @()
        }

        $schema = if ($WithSchemas.ContainsKey($stepType)) {
            $WithSchemas[$stepType]
        }
        else {
            # Default: permissive schema that accepts any With key
            @{ Keys = @{}; AllowAdditionalKeys = $true }
        }

        $metadata[$stepType] = @{
            RequiredCapabilities = $caps
            WithSchema           = $schema
        }

        if ($Providers.ContainsKey($stepType)) {
            $metadata[$stepType]['Provider'] = @{ DefaultAlias = [string]$Providers[$stepType] }
        }
    }

    return $metadata
}

function Invoke-IdleTestStepHandler {
    <#
    .SYNOPSIS
    Invokes a step handler the way the engine does.

    .DESCRIPTION
    Validates Step.With against the step metadata catalog (plan-time contract: types, defaults, Provider
    alias), builds the handler arguments (-Context, -With, -Provider handle, -Step) and converts the handler
    output into an IdLE.StepResult. Use it in step unit tests instead of calling the handler directly.

    .PARAMETER Context
    Execution context (Providers, EventSink, optional AcquireAuthSession).

    .PARAMETER Step
    Step definition with Name, Type and With.

    .PARAMETER StepMetadata
    Optional metadata catalog for host-defined step types (Providers.StepMetadata shape).

    .PARAMETER StepRegistry
    Optional handler registry for host-defined step types (Providers.StepRegistry shape).

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter()]
        [hashtable] $StepMetadata,

        [Parameter()]
        [hashtable] $StepRegistry
    )

    $core = Get-Module -Name 'IdLE.Core' -All | Select-Object -First 1
    & $core {
        param($Context, $Step, $StepMetadata, $StepRegistry)

        # Workflow inputs are data-only; the engine rejects ScriptBlocks before planning.
        $stepWith = Get-IdlePropertyValue -Object $Step -Name 'With'
        Assert-IdleNoScriptBlock -InputObject $stepWith -Path 'With'

        $hostProviders = @{}
        if ($null -ne $StepMetadata) { $hostProviders.StepMetadata = $StepMetadata }
        if ($null -ne $StepRegistry) { $hostProviders.StepRegistry = $StepRegistry }

        $stepName = [string]$Step.Name
        $stepType = [string]$Step.Type
        $catalog = Resolve-IdleStepMetadataCatalog -Providers $hostProviders
        $with = ConvertTo-IdleStepWith -Metadata $catalog[$stepType] -With (Copy-IdleDataObject -Value $stepWith) -StepName $stepName -StepType $stepType

        $planStep = [pscustomobject]@{ Name = $stepName; Type = $stepType; With = $with }
        $handler = Resolve-IdleStepHandler -StepType $stepType -StepRegistry (Get-IdleStepRegistry -Providers $hostProviders)
        $handlerArguments = New-IdleStepHandlerArguments -Handler $handler -Step $planStep -Context $Context
        $output = & $handler @handlerArguments

        ConvertTo-IdleStepResult -Output $output -StepName $stepName -StepType $stepType -Attempts 1 -Source $null
    } $Context $Step $StepMetadata $StepRegistry
}

function New-IdleTestEventSink {
    <#
    .SYNOPSIS
    Creates an event sink for step unit tests.

    .DESCRIPTION
    Provides the engine's event contract WriteEvent(Type, Message, StepName, Data[, Level]) and records
    every event in the Events list.

    .OUTPUTS
    PSCustomObject with Events (List[object]) and a WriteEvent script method.
    #>
    [CmdletBinding()]
    param()

    $sink = [pscustomobject]@{
        Events = [System.Collections.Generic.List[object]]::new()
    }

    $null = Add-Member -InputObject $sink -MemberType ScriptMethod -Name WriteEvent -Value {
        param($Type, $Message, $StepName, $Data, $Level)
        $this.Events.Add([pscustomobject]@{ Type = $Type; Message = $Message; StepName = $StepName; Data = $Data; Level = $Level })
    }

    return $sink
}
