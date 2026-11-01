Set-StrictMode -Version Latest

function ConvertTo-IdleWorkflowSteps {
    <#
    .SYNOPSIS
    Normalizes workflow steps into IdLE.PlanStep objects.

    .DESCRIPTION
    Evaluates Condition during planning and sets Status = Planned / NotApplicable.

    When a step's Condition evaluates to false, the step is marked NotApplicable and all
    subsequent plan-time processing that only makes sense for executable steps (With template
    resolution and WithSchema validation) is skipped for that step. This prevents false-positive
    planning failures caused by missing data referenced in With blocks that are intentionally
    guarded by a Condition.

    Condition path validation uses -ExcludeExistsOperatorPaths so that steps using the Exists
    operator to guard optional context attributes are not rejected at plan time merely because
    the attribute is absent — that is the intended use of the Exists operator.

    Step State (see docs/extend/steps.md):
    - Condition must not reference State.* (StateReferenceNotAllowed).
    - With strings with State placeholders are kept for execution-time resolution (DeferredWith).
    - State references in Precondition and DeferredWith are validated against StateProducers
      (steps that run before), which is extended with every normalized step.

    IMPORTANT:
    WorkflowSteps is optional and may be null or empty. A workflow is allowed to omit
    OnFailureSteps entirely. Therefore we must not mark this parameter as Mandatory.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $WorkflowSteps,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $PlanningContext,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $StepMetadataCatalog,

        # Step name -> StateSchema of the steps that run before this collection (extended in place).
        [Parameter()]
        [AllowNull()]
        [hashtable] $StateProducers,

        # Step names that exist in both Steps and OnFailureSteps (passed for OnFailureSteps only).
        [Parameter()]
        [string[]] $AmbiguousStateNames = @()
    )

    if ($null -eq $StateProducers) {
        $StateProducers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    $isStatePath = { param([string] $Path) $Path -eq 'State' -or $Path.StartsWith('State.', [System.StringComparison]::OrdinalIgnoreCase) }

    if ($null -eq $WorkflowSteps -or @($WorkflowSteps).Count -eq 0) {
        return @()
    }

    $normalizedSteps = @()

    foreach ($s in @($WorkflowSteps)) {
        $stepName = if (Test-IdleWorkflowStepKey -Step $s -Key 'Name') {
            [string](Get-IdlePropertyValue -Object $s -Name 'Name')
        }
        else {
            ''
        }

        if ([string]::IsNullOrWhiteSpace($stepName)) {
            throw [System.ArgumentException]::new('Workflow step is missing required key "Name".', 'Workflow')
        }

        $stepType = if (Test-IdleWorkflowStepKey -Step $s -Key 'Type') {
            [string](Get-IdlePropertyValue -Object $s -Name 'Type')
        }
        else {
            ''
        }

        if ([string]::IsNullOrWhiteSpace($stepType)) {
            throw [System.ArgumentException]::new(("Workflow step '{0}' is missing required key 'Type'." -f $stepName), 'Workflow')
        }

        if (Test-IdleWorkflowStepKey -Step $s -Key 'When') {
            throw [System.ArgumentException]::new(
                ("Workflow step '{0}' uses key 'When'. 'When' has been renamed to 'Condition'. Please update the workflow definition." -f $stepName),
                'Workflow'
            )
        }

        $condition = if (Test-IdleWorkflowStepKey -Step $s -Key 'Condition') {
            Get-IdlePropertyValue -Object $s -Name 'Condition'
        }
        else {
            $null
        }

        $status = 'Planned'
        if ($null -ne $condition) {
            $schemaErrors = Test-IdleConditionSchema -Condition $condition -StepName $stepName
            if (@($schemaErrors).Count -gt 0) {
                throw [System.ArgumentException]::new(
                    ("Invalid Condition on step '{0}': {1}" -f $stepName, ([string]::Join(' ', @($schemaErrors)))),
                    'Workflow'
                )
            }

            foreach ($conditionPath in @(Get-IdleConditionPath -Condition $condition)) {
                if (& $isStatePath $conditionPath.Path) {
                    throw [System.ArgumentException]::new(
                        ("StateReferenceNotAllowed: Workflow step '{0}' references '{1}' in Condition. Conditions are evaluated at planning time, before any step has run; use a Precondition instead." -f $stepName, $conditionPath.Path),
                        'Workflow'
                    )
                }
            }

            Assert-IdleConditionPathsResolvable -Condition $condition -Context $PlanningContext -StepName $stepName -Source 'Condition' -ExcludeExistsOperatorPaths

            $isApplicable = Test-IdleCondition -Condition $condition -Context $PlanningContext
            if (-not $isApplicable) {
                $status = 'NotApplicable'
            }
        }

        # Derive RequiresCapabilities from StepMetadataCatalog instead of workflow.
        $requiresCaps = @()
        if ($StepMetadataCatalog.ContainsKey($stepType)) {
            $metadata = $StepMetadataCatalog[$stepType]
            if ($null -ne $metadata -and $metadata -is [hashtable] -and $metadata.ContainsKey('RequiredCapabilities')) {
                $requiresCaps = ConvertTo-IdleRequiredCapabilities -Value $metadata['RequiredCapabilities'] -StepName $stepName
            }
        }
        else {
            # Workflow references a Step.Type for which no StepMetadata entry is available - fail fast.
            $errorMessage = "MissingStepTypeMetadata: Workflow step '$stepName' references step type '$stepType' which has no metadata entry. " + `
                "To resolve this: (1) Import/load the step pack module (manifest PrivateData.IdLE.Kind = 'StepPack') that provides metadata for '$stepType', OR " + `
                "(2) For host-defined/custom step types only, provide Providers.StepMetadata['$stepType'] = @{ RequiredCapabilities = @(...) }."
            throw [System.InvalidOperationException]::new($errorMessage)
        }

        $description = if (Test-IdleWorkflowStepKey -Step $s -Key 'Description') {
            [string](Get-IdlePropertyValue -Object $s -Name 'Description')
        }
        else {
            ''
        }

        $with = if (Test-IdleWorkflowStepKey -Step $s -Key 'With') {
            Copy-IdleDataObject -Value (Get-IdlePropertyValue -Object $s -Name 'With')
        }
        else {
            @{}
        }

        # Skip With template resolution and WithSchema validation for NotApplicable steps.
        # A step whose Condition evaluated to false will never be executed, so further plan-time
        # validation that assumes the step is eligible would produce false-positive failures.
        $deferredWith = @()
        $stateReferences = [System.Collections.Generic.List[object]]::new()
        if ($status -ne 'NotApplicable') {
            # Resolve template placeholders in With (planning-time resolution).
            # Strings with State placeholders stay unresolved until the step runs.
            $deferredList = [System.Collections.Generic.List[object]]::new()
            $with = Resolve-IdleWorkflowTemplates -Value $with -Request $PlanningContext.Request -StepName $stepName -DeferredList $deferredList

            foreach ($deferred in $deferredList) {
                $rootKey = [string]@($deferred.Segments)[0]
                if (@('Provider', 'AuthSessionName', 'AuthSessionOptions') -contains $rootKey) {
                    throw [System.ArgumentException]::new(
                        ("StateReferenceNotAllowed: Workflow step '{0}' references State in {1}. Provider routing and authentication are resolved at planning time." -f $stepName, $deferred.Path),
                        'Workflow'
                    )
                }
                foreach ($statePath in $deferred.StatePaths) {
                    $stateReferences.Add(@{ Path = $statePath; Source = $deferred.Path })
                }
            }

            # Validate With against the typed WithSchema (fail-fast plan-time check) and apply defaults,
            # so the plan carries the effective With (including the resolved Provider alias).
            # Deferred values are validated against their key schema after execution-time resolution.
            $deferredSchemas = @{}
            $with = ConvertTo-IdleStepWith -Metadata $StepMetadataCatalog[$stepType] -With $with -StepName $stepName -StepType $stepType `
                -DeferredPaths @($deferredList | ForEach-Object { $_.Path }) -DeferredSchemas $deferredSchemas

            # Sorted by path: With is a hashtable, and plans must not depend on its enumeration order.
            $deferredWith = @(foreach ($deferred in @($deferredList | Sort-Object -Property { $_.Path })) {
                    @{
                        Path     = $deferred.Path
                        Segments = @($deferred.Segments)
                        Schema   = if ($deferredSchemas.ContainsKey($deferred.Path)) { Copy-IdleDataObject -Value $deferredSchemas[$deferred.Path] } else { $null }
                    }
                })
        }

        $retryProfile = if (Test-IdleWorkflowStepKey -Step $s -Key 'RetryProfile') {
            [string](Get-IdlePropertyValue -Object $s -Name 'RetryProfile')
        }
        else {
            $null
        }

        $planWarnings = $null
        $planObj = $PlanningContext.Plan
        if ($null -ne $planObj) {
            if ($planObj -is [System.Collections.IDictionary]) {
                if ($planObj.Contains('Warnings')) { $planWarnings = $planObj['Warnings'] }
            } else {
                $wProp = $planObj.PSObject.Properties['Warnings']
                if ($null -ne $wProp) { $planWarnings = $wProp.Value }
            }
        }
        $planWarningsCanTrackCount = $planWarnings -is [System.Collections.IList]
        $warningCountBefore = if ($planWarningsCanTrackCount) { [int]$planWarnings.Count } else { 0 }

        $preconditionSettings = ConvertTo-IdleWorkflowStepPreconditionSettings -Step $s -StepName $stepName -PlanningContext $PlanningContext
        $precondition = $preconditionSettings.Precondition
        $onPreconditionFalse = $preconditionSettings.OnPreconditionFalse
        $preconditionEvent = $preconditionSettings.PreconditionEvent
        $preconditionWarnings = @()

        if ($null -ne $precondition) {
            foreach ($preconditionPath in @(Get-IdleConditionPath -Condition $precondition)) {
                if (& $isStatePath $preconditionPath.Path) {
                    $stateReferences.Add(@{ Path = $preconditionPath.Path; Source = 'Precondition' })
                }
            }
        }

        foreach ($reference in $stateReferences) {
            # Normalize the root casing so that 'state.X' and 'State.X' are validated alike.
            $referencePath = 'State' + $reference.Path.Substring(5)
            Assert-IdleStateReference -Path $referencePath -StepName $stepName -Source $reference.Source -Producers $StateProducers -AmbiguousNames $AmbiguousStateNames
        }

        # The step's published State (if any) is visible to the steps that follow it.
        $stateSchema = Get-IdleStepStateSchema -Metadata $StepMetadataCatalog[$stepType]
        $StateProducers[$stepName] = $stateSchema

        if ($planWarningsCanTrackCount) {
            $warningCountAfter = [int]$planWarnings.Count
            if ($warningCountAfter -gt $warningCountBefore) {
                for ($warningIndex = $warningCountBefore; $warningIndex -lt $warningCountAfter; $warningIndex++) {
                    $warning = $planWarnings[$warningIndex]
                    $warningSource = Get-IdlePropertyValue -Object $warning -Name 'Source'
                    $warningStep = Get-IdlePropertyValue -Object $warning -Name 'Step'
                    if ($warningSource -eq 'Precondition' -and $warningStep -eq $stepName) {
                        $preconditionWarnings += $warning
                    }
                }
            }
        }

        $normalizedSteps += [pscustomobject]@{
            PSTypeName           = 'IdLE.PlanStep'
            Name                 = $stepName
            Type                 = $stepType
            Description          = $description
            Condition            = Copy-IdleDataObject -Value $condition
            Precondition         = $precondition
            OnPreconditionFalse  = $onPreconditionFalse
            PreconditionEvent    = $preconditionEvent
            Warnings             = $preconditionWarnings
            With                 = $with
            DeferredWith         = $deferredWith
            StateSchema          = $stateSchema
            RequiresCapabilities = $requiresCaps
            Status               = $status
            RetryProfile         = $retryProfile
        }
    }

    # IMPORTANT:
    # Returning an empty array variable can produce no pipeline output, resulting in $null on assignment.
    # Force a stable array output shape.
    return @($normalizedSteps)
}
