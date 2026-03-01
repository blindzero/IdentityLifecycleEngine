Set-StrictMode -Version Latest

function ConvertTo-IdleWorkflowSteps {
    <#
    .SYNOPSIS
    Normalizes workflow steps into IdLE.PlanStep objects.

    .DESCRIPTION
    Evaluates Condition during planning and sets Status = Planned / NotApplicable.

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
        [hashtable] $StepMetadataCatalog
    )

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

            Assert-IdleConditionPathsResolvable -Condition $condition -Context $PlanningContext -StepName $stepName -Source 'Condition'

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
                "To resolve this: (1) Import/load the step pack module (IdLE.Steps.*) that provides metadata for '$stepType' via Get-IdleStepMetadataCatalog, OR " + `
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

        # Resolve template placeholders in With (planning-time resolution)
        $with = Resolve-IdleWorkflowTemplates -Value $with -Request $PlanningContext.Request -StepName $stepName

        # Validate AllowedWithKeys declared by step metadata (fail-fast plan-time schema check).
        # Steps that declare AllowedWithKeys accept only those keys in With; any other key is rejected.
        # Steps that do not declare AllowedWithKeys skip this validation (backward compatible).
        if ($StepMetadataCatalog.ContainsKey($stepType)) {
            $md = $StepMetadataCatalog[$stepType]
            if ($null -ne $md -and $md -is [hashtable] -and $md.ContainsKey('AllowedWithKeys')) {
                $allowedSet = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]@($md['AllowedWithKeys']),
                    [System.StringComparer]::OrdinalIgnoreCase
                )
                foreach ($wk in @($with.Keys)) {
                    if (-not $allowedSet.Contains([string]$wk)) {
                        $allowedList = [string]::Join(', ', ([string[]]@($md['AllowedWithKeys']) | Sort-Object))
                        throw [System.ArgumentException]::new(
                            ("Step '{0}' (type '{1}') does not support With.{2}. Allowed With keys: {3}." -f $stepName, $stepType, [string]$wk, $allowedList),
                            'Workflow'
                        )
                    }
                }
            }
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
