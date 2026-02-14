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

        $retryProfile = if (Test-IdleWorkflowStepKey -Step $s -Key 'RetryProfile') {
            [string](Get-IdlePropertyValue -Object $s -Name 'RetryProfile')
        }
        else {
            $null
        }

        $normalizedSteps += [pscustomobject]@{
            PSTypeName           = 'IdLE.PlanStep'
            Name                 = $stepName
            Type                 = $stepType
            Description          = $description
            Condition            = Copy-IdleDataObject -Value $condition
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
